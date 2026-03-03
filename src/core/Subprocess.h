#pragma once

// ── Subprocess.h ────────────────────────────────────────────────────────────────
// Safe, cancellable subprocess execution.
//
// Basic (blocking) usage — fire and forget:
//   int rc = Process::run("ffmpeg", {"-y", "-i", input, output});
//
// Cancellable usage — for long-running conversions:
//   Process p;
//   p.start("ffmpeg", {"-y", "-i", input, output});
//   while (!p.finished()) {
//       if (cancelFlag) { p.cancel(); break; }
//       std::this_thread::sleep_for(50ms);
//   }
//   int rc = p.wait();  // always call wait() to reap the process

#include <string>
#include <vector>
#include <thread>
#include <chrono>

#ifdef _WIN32
#  define WIN32_LEAN_AND_MEAN
#  include <windows.h>
#else
#  include <sys/types.h>
#  include <sys/wait.h>
#  include <unistd.h>
#  include <signal.h>
#  include <fcntl.h>
#  include <errno.h>
#endif

namespace converter {

class Process {
public:
    Process() = default;

    // Non-copyable — owns a process handle
    Process(const Process&)            = delete;
    Process& operator=(const Process&) = delete;

    ~Process() {
        // If caller forgot to wait(), kill and reap to avoid orphans
        if (running()) {
            cancel();
            wait();
        }
    }

    // ── Blocking convenience wrapper ──────────────────────────────────────────
    static int run(const std::string& executable, const std::vector<std::string>& args) {
        Process p;
        if (!p.start(executable, args)) return -1;
        return p.wait();
    }

    // ── Non-blocking start ────────────────────────────────────────────────────
    // Returns false if the process could not be launched.
    bool start(const std::string& executable, const std::vector<std::string>& args) {
#ifdef _WIN32
        return startWindows(executable, args);
#else
        return startPosix(executable, args);
#endif
    }

    // ── Poll — returns true if the process has exited ─────────────────────────
    bool finished() const {
#ifdef _WIN32
        if (m_handle == INVALID_HANDLE_VALUE) return true;
        return WaitForSingleObject(m_handle, 0) == WAIT_OBJECT_0;
#else
        if (m_pid <= 0) return true;
        int status;
        pid_t r = waitpid(m_pid, &status, WNOHANG);
        if (r == m_pid) {
            // Store exit code and mark done
            const_cast<Process*>(this)->m_exitCode =
                WIFEXITED(status) ? WEXITSTATUS(status) : -1;
            const_cast<Process*>(this)->m_pid = -1;
            return true;
        }
        return false;
#endif
    }

    bool running() const { return !finished(); }

    // ── Kill the process ──────────────────────────────────────────────────────
    // Sends SIGKILL on Linux, TerminateProcess on Windows.
    // Always call wait() after cancel() to reap the process.
    void cancel() {
#ifdef _WIN32
        if (m_handle != INVALID_HANDLE_VALUE)
            TerminateProcess(m_handle, 1);
#else
        if (m_pid > 0)
            kill(m_pid, SIGKILL);
#endif
    }

    // ── Wait for exit and return exit code ────────────────────────────────────
    // Safe to call even if the process already finished or was never started.
    int wait() {
#ifdef _WIN32
        if (m_handle == INVALID_HANDLE_VALUE) return m_exitCode;
        WaitForSingleObject(m_handle, INFINITE);
        DWORD code = 1;
        GetExitCodeProcess(m_handle, &code);
        CloseHandle(m_handle);
        CloseHandle(m_thread);
        m_handle = INVALID_HANDLE_VALUE;
        m_thread = INVALID_HANDLE_VALUE;
        m_exitCode = static_cast<int>(code);
        return m_exitCode;
#else
        if (m_pid <= 0) return m_exitCode;
        int status = 0;
        waitpid(m_pid, &status, 0);
        m_pid = -1;
        m_exitCode = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
        return m_exitCode;
#endif
    }

    // ── Blocking run with cancel-flag polling ─────────────────────────────────
    // Polls every `pollMs` milliseconds. Returns -2 if cancelled.
    // If the cancel flag is already set before the process starts, the process
    // is never spawned and -2 is returned immediately (avoids an unnecessary
    // fork+kill cycle that can generate spurious signals on some platforms).
    static int runCancellable(
        const std::string& executable,
        const std::vector<std::string>& args,
        std::atomic<bool>* cancelFlag,
        int pollMs = 50)
    {
        // Early-exit: don't spawn a process we'd immediately kill
        if (cancelFlag && cancelFlag->load()) return -2;

        Process p;
        if (!p.start(executable, args)) return -1;

        while (!p.finished()) {
            if (cancelFlag && cancelFlag->load()) {
                p.cancel();
                p.wait();
                return -2;  // sentinel: cancelled
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(pollMs));
        }

        return p.wait();
    }

private:

#ifndef _WIN32
    pid_t m_pid      = -1;
    int   m_exitCode = -1;

    bool startPosix(const std::string& executable, const std::vector<std::string>& args) {
        std::vector<const char*> argv;
        argv.reserve(args.size() + 2);
        argv.push_back(executable.c_str());
        for (auto& a : args) argv.push_back(a.c_str());
        argv.push_back(nullptr);

        pid_t pid = fork();
        if (pid < 0) return false;

        if (pid == 0) {
            // Child: redirect stdout+stderr to /dev/null
            int devnull = open("/dev/null", O_WRONLY);
            if (devnull >= 0) {
                dup2(devnull, STDOUT_FILENO);
                dup2(devnull, STDERR_FILENO);
                close(devnull);
            }
            execvp(executable.c_str(), const_cast<char* const*>(argv.data()));
            _exit(127);
        }

        m_pid = pid;
        return true;
    }
#endif

#ifdef _WIN32
    HANDLE m_handle  = INVALID_HANDLE_VALUE;
    HANDLE m_thread  = INVALID_HANDLE_VALUE;
    int    m_exitCode = -1;

    bool startWindows(const std::string& executable, const std::vector<std::string>& args) {
        std::string cmdLine = quoteArg(executable);
        for (auto& a : args) { cmdLine += ' '; cmdLine += quoteArg(a); }

        STARTUPINFOA si = {};
        si.cb      = sizeof(si);
        si.dwFlags = STARTF_USESTDHANDLES;

        HANDLE nul = CreateFileA("NUL", GENERIC_WRITE, FILE_SHARE_WRITE,
            nullptr, OPEN_EXISTING, 0, nullptr);
        si.hStdInput  = GetStdHandle(STD_INPUT_HANDLE);
        si.hStdOutput = nul;
        si.hStdError  = nul;

        PROCESS_INFORMATION pi = {};
        BOOL ok = CreateProcessA(nullptr, cmdLine.data(),
            nullptr, nullptr, TRUE, CREATE_NEW_PROCESS_GROUP, nullptr, nullptr, &si, &pi);

        if (nul != INVALID_HANDLE_VALUE) CloseHandle(nul);
        if (!ok) return false;

        m_handle = pi.hProcess;
        m_thread = pi.hThread;
        return true;
    }

    static std::string quoteArg(const std::string& arg) {
        if (arg.find_first_of(" \t\n\r\"") == std::string::npos) return arg;
        std::string out = "\"";
        for (char c : arg) {
            if (c == '"') out += "\\\"";
            else          out += c;
        }
        out += '"';
        return out;
    }
#endif
};

} // namespace converter
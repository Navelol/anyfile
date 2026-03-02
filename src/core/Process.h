#pragma once

// ── Process.h ─────────────────────────────────────────────────────────────────
// Safe subprocess execution — args passed directly to the OS, never through a
// shell. Eliminates injection via filenames containing ; & | $ ` etc.
//
// Usage:
//   int rc = Process::run("ffmpeg", {"-y", "-i", inputPath, outputPath});
//   if (rc != 0) // handle error
//
// All args are plain strings. No quoting, no escaping needed by the caller.

#include <string>
#include <vector>

#ifdef _WIN32
#  define WIN32_LEAN_AND_MEAN
#  include <windows.h>
#else
#  include <sys/types.h>
#  include <sys/wait.h>
#  include <unistd.h>
#  include <errno.h>
#endif

namespace converter {

class Process {
public:
    // Run `executable` with `args` (not including argv[0] — we add that).
    // Stdout and stderr are suppressed (equivalent to the old 2>/dev/null).
    // Returns the process exit code, or -1 on launch failure.
    static int run(const std::string& executable, const std::vector<std::string>& args) {
#ifdef _WIN32
        return runWindows(executable, args);
#else
        return runPosix(executable, args);
#endif
    }

private:

#ifndef _WIN32
    // ── POSIX: fork + execvp ──────────────────────────────────────────────────
    static int runPosix(const std::string& executable, const std::vector<std::string>& args) {
        // Build argv: [executable, arg0, arg1, ..., nullptr]
        std::vector<const char*> argv;
        argv.reserve(args.size() + 2);
        argv.push_back(executable.c_str());
        for (auto& a : args) argv.push_back(a.c_str());
        argv.push_back(nullptr);

        pid_t pid = fork();

        if (pid < 0)
            return -1;  // fork failed

        if (pid == 0) {
            // ── Child process ─────────────────────────────────────────────────
            // Redirect stdout + stderr to /dev/null
            int devnull = open("/dev/null", O_WRONLY);
            if (devnull >= 0) {
                dup2(devnull, STDOUT_FILENO);
                dup2(devnull, STDERR_FILENO);
                close(devnull);
            }
            // execvp searches PATH, just like system() would
            execvp(executable.c_str(), const_cast<char* const*>(argv.data()));
            // If we get here, exec failed
            _exit(127);
        }

        // ── Parent process ────────────────────────────────────────────────────
        int status = 0;
        if (waitpid(pid, &status, 0) < 0)
            return -1;

        if (WIFEXITED(status))
            return WEXITSTATUS(status);

        // Killed by signal
        return -1;
    }
#endif

#ifdef _WIN32
    // ── Windows: CreateProcess ────────────────────────────────────────────────
    static int runWindows(const std::string& executable, const std::vector<std::string>& args) {
        // Build a properly quoted command line for CreateProcess.
        // CreateProcess does NOT use a shell but it does re-parse the command
        // line string via CommandLineToArgvW rules, so we must quote args that
        // contain spaces or quotes.
        std::string cmdLine = quoteArg(executable);
        for (auto& a : args) {
            cmdLine += ' ';
            cmdLine += quoteArg(a);
        }

        STARTUPINFOA si = {};
        si.cb          = sizeof(si);
        si.dwFlags     = STARTF_USESTDHANDLES;

        // Redirect stdout + stderr to NUL
        HANDLE nul = CreateFileA(
            "NUL", GENERIC_WRITE, FILE_SHARE_WRITE,
            nullptr, OPEN_EXISTING, 0, nullptr);
        si.hStdInput  = GetStdHandle(STD_INPUT_HANDLE);
        si.hStdOutput = nul;
        si.hStdError  = nul;

        PROCESS_INFORMATION pi = {};
        BOOL ok = CreateProcessA(
            nullptr,
            cmdLine.data(),   // mutable copy required by API
            nullptr, nullptr,
            TRUE,             // inherit handles (for NUL redirect)
            0, nullptr, nullptr,
            &si, &pi);

        if (nul != INVALID_HANDLE_VALUE) CloseHandle(nul);

        if (!ok) return -1;

        WaitForSingleObject(pi.hProcess, INFINITE);

        DWORD exitCode = 1;
        GetExitCodeProcess(pi.hProcess, &exitCode);

        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);

        return static_cast<int>(exitCode);
    }

    // Quote a single argument using Windows CommandLineToArgvW rules:
    // wrap in double-quotes, escape internal double-quotes as \"
    static std::string quoteArg(const std::string& arg) {
        // No special chars — no quoting needed
        if (arg.find_first_of(" \t\n\r\"") == std::string::npos)
            return arg;

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
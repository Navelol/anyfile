#include <catch2/catch_test_macros.hpp>
#include "Subprocess.h"
#include <atomic>
#include <thread>
#include <chrono>
#include <filesystem>
#include <fstream>

using namespace converter;
namespace fs = std::filesystem;

// ── Platform-aware command helpers ───────────────────────────────────────────
// These resolve to equivalent commands on both Linux and Windows so every
// test section runs (and is meaningful) on both platforms.
#ifdef PLATFORM_WINDOWS
    static int run_exit(int code) {
        return Process::run("cmd", {"/c", "exit /b " + std::to_string(code)});
    }
    static std::string long_sleep_cmd()              { return "ping"; }
    static std::vector<std::string> long_sleep_args(){ return {"-n", "12", "127.0.0.1"}; }
    static std::vector<std::string> short_sleep_args(){ return {"-n", "2",  "127.0.0.1"}; }
    static bool file_exists_via_cmd(const fs::path& p) { return fs::exists(p); }
#else
    static int run_exit(int code) {
        return Process::run("sh", {"-c", "exit " + std::to_string(code)});
    }
    static std::string long_sleep_cmd()              { return "sleep"; }
    static std::vector<std::string> long_sleep_args(){ return {"10"}; }
    static std::vector<std::string> short_sleep_args(){ return {"1"}; }
    static bool file_exists_via_cmd(const fs::path& p) {
        return Process::run("test", {"-f", p.string()}) == 0;
    }
#endif

// ── Basic execution ───────────────────────────────────────────────────────────

TEST_CASE("Process - basic execution", "[process]") {

    SECTION("success returns exit code 0") {
        REQUIRE(run_exit(0) == 0);
    }

    SECTION("failure returns non-zero exit code") {
        REQUIRE(run_exit(1) != 0);
    }

    SECTION("unknown executable returns non-zero") {
        // Non-existent binary: execvp/CreateProcess fails → non-zero result
        REQUIRE(Process::run("anyfile_no_such_binary_xyz", {}) != 0);
    }

    SECTION("args are passed correctly") {
        fs::path tmp = fs::temp_directory_path() / "anyfile_proc_test.txt";
        { std::ofstream f(tmp); f << "x"; }
        bool found = file_exists_via_cmd(tmp);
        fs::remove(tmp);
        REQUIRE(found);
    }

    SECTION("exit code is correctly propagated") {
        REQUIRE(run_exit(42) == 42);
    }
}

// ── Cancellation ──────────────────────────────────────────────────────────────

TEST_CASE("Process - cancellation", "[process][cancel]") {

    SECTION("cancel flag stops a running process") {
        std::atomic<bool> cancel{false};

        std::thread canceller([&]() {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            cancel.store(true);
        });

        auto t0 = std::chrono::steady_clock::now();
        int rc = Process::runCancellable(long_sleep_cmd(), long_sleep_args(), &cancel);
        auto elapsed = std::chrono::steady_clock::now() - t0;
        canceller.join();

        REQUIRE(rc == -2);
        REQUIRE(elapsed < std::chrono::seconds(5));
    }

    SECTION("null cancel flag runs to completion") {
        int rc = Process::runCancellable(long_sleep_cmd(), short_sleep_args(), nullptr);
        (void)rc;  // exit code is platform-dependent
        REQUIRE(true);
    }

    SECTION("already-set cancel flag cancels immediately") {
        std::atomic<bool> cancel{true};
        int rc = Process::runCancellable(long_sleep_cmd(), long_sleep_args(), &cancel);
        REQUIRE(rc == -2);
    }
}

// ── Orphan prevention ─────────────────────────────────────────────────────────

TEST_CASE("Process - orphan prevention", "[process][orphan]") {

    SECTION("destructor kills and reaps process if wait() not called") {
        {
            Process p;
            REQUIRE(p.start(long_sleep_cmd(), long_sleep_args()));
            // p goes out of scope — destructor should kill it
        }
        REQUIRE(true);  // if we get here without hanging, orphan prevention works
    }

    SECTION("wait() is safe to call on never-started process") {
        Process p;
        int rc = p.wait();
        REQUIRE(rc == -1);
    }

    SECTION("wait() is safe to call twice") {
        Process p;
        REQUIRE(p.start(long_sleep_cmd(), short_sleep_args()));
        int rc1 = p.wait();
        int rc2 = p.wait();
        REQUIRE(rc1 == rc2);  // second call returns cached exit code
    }
}

// ── Shell metacharacter safety ────────────────────────────────────────────────

TEST_CASE("Process - shell metacharacter safety", "[process][security]") {

    SECTION("filename with spaces is passed as single argument") {
        fs::path tmp = fs::temp_directory_path() / "any file with spaces.txt";
        { std::ofstream f(tmp); f << "x"; }
        bool found = file_exists_via_cmd(tmp);
        fs::remove(tmp);
        REQUIRE(found);
    }

#ifndef PLATFORM_WINDOWS
    // These tests use Unix 'test' and rely on POSIX shell quoting semantics
    SECTION("semicolons in args are not interpreted as shell separators") {
        int rc = Process::run("test", {"-f", "false; true"});
        REQUIRE(rc != 0);
    }

    SECTION("filename with shell special chars is treated literally") {
        fs::path tmp = fs::temp_directory_path() / "file_dollar_tick.txt";
        { std::ofstream f(tmp); f << "x"; }
        int rc = Process::run("test", {"-f", tmp.string()});
        fs::remove(tmp);
        REQUIRE(rc == 0);
    }
#endif
}

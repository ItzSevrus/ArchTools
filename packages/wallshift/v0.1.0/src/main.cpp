#include <algorithm>
#include <chrono>
#include <cerrno>
#include <cctype>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <fcntl.h>
#include <random>
#include <string>
#include <thread>
#include <vector>

#include <sys/types.h>
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>

namespace fs = std::filesystem;

struct Options {
    fs::path directory;
    std::chrono::seconds interval{300};
    bool random_mode = false;
    bool shuffle_mode = false;
    bool once = false;
    bool help = false;
};

void print_help(const char* program) {
    std::cout
        << "Wallshift - lightweight wallpaper rotation for Linux/Wayland\n\n"
        << "Usage: " << program << " [options]\n\n"
        << "Options:\n"
        << "  -d, --dir PATH        Wallpaper directory (default: ~/Pictures/wallpapers)\n"
        << "  -i, --interval TIME   Change interval: 30s, 5m, 1h, or bare seconds\n"
        << "  -r, --random          Pick a random image each time (may repeat)\n"
        << "  -s, --shuffle         Shuffle a cycle; each image appears once per cycle\n"
        << "  -1, --once            Set one wallpaper and exit\n"
        << "  -h, --help            Show this help\n\n"
        << "Examples:\n"
        << "  " << program << " --interval 10m --shuffle\n"
        << "  " << program << " --dir ~/Pictures/Nature --interval 30s --random\n"
        << "  " << program << " --once\n\n"
        << "Wallshift uses 'awww img' to apply wallpapers. Start awww-daemon first.\n";
}

std::string expand_home(std::string value) {
    if (!value.empty() && value[0] == '~') {
        const char* home = std::getenv("HOME");
        if (home && (value.size() == 1 || value[1] == '/'))
            return std::string(home) + value.substr(1);
    }
    return value;
}

bool parse_interval(const std::string& input, std::chrono::seconds& result) {
    if (input.empty()) return false;

    std::size_t digits = 0;
    while (digits < input.size() &&
           std::isdigit(static_cast<unsigned char>(input[digits]))) {
        ++digits;
    }
    if (digits == 0) return false;

    long long amount = 0;
    try {
        amount = std::stoll(input.substr(0, digits));
    } catch (...) {
        return false;
    }

    std::string unit = input.substr(digits);
    long long multiplier = 1;
    if (unit.empty() || unit == "s") multiplier = 1;
    else if (unit == "m") multiplier = 60;
    else if (unit == "h") multiplier = 3600;
    else if (unit == "d") multiplier = 86400;
    else return false;

    if (amount <= 0 || amount > 31536000 / multiplier) return false;
    result = std::chrono::seconds(amount * multiplier);
    return true;
}

bool parse_args(int argc, char** argv, Options& options) {
    const char* home = std::getenv("HOME");
    if (!home) {
        std::cerr << "Error: HOME environment variable is not set.\n";
        return false;
    }
    options.directory = fs::path(home) / "Pictures" / "wallpapers";

    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        auto require_value = [&](const char* name) -> const char* {
            if (i + 1 >= argc) {
                std::cerr << "Error: " << name << " requires a value.\n";
                return nullptr;
            }
            return argv[++i];
        };

        if (arg == "-h" || arg == "--help") options.help = true;
        else if (arg == "-1" || arg == "--once") options.once = true;
        else if (arg == "-r" || arg == "--random") {
            options.random_mode = true;
            options.shuffle_mode = false;
        } else if (arg == "-s" || arg == "--shuffle") {
            options.shuffle_mode = true;
            options.random_mode = false;
        } else if (arg == "-d" || arg == "--dir") {
            const char* value = require_value(arg.c_str());
            if (!value) return false;
            options.directory = expand_home(value);
        } else if (arg == "-i" || arg == "--interval") {
            const char* value = require_value(arg.c_str());
            if (!value) return false;
            if (!parse_interval(value, options.interval)) {
                std::cerr << "Error: invalid interval '" << value
                          << "'. Use a positive value such as 30s, 5m, or 1h.\n";
                return false;
            }
        } else {
            std::cerr << "Error: unknown option '" << arg << "'. Use --help.\n";
            return false;
        }
    }
    return true;
}

bool is_image(const fs::path& path) {
    std::string ext = path.extension().string();
    std::transform(ext.begin(), ext.end(), ext.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return ext == ".jpg" || ext == ".jpeg" || ext == ".png" ||
           ext == ".webp" || ext == ".bmp" || ext == ".gif" ||
           ext == ".tif" || ext == ".tiff" || ext == ".avif";
}

std::vector<fs::path> find_images(const fs::path& directory) {
    std::vector<fs::path> images;
    std::error_code ec;
    fs::recursive_directory_iterator it(
        directory, fs::directory_options::skip_permission_denied, ec), end;

    for (; it != end; it.increment(ec)) {
        if (ec) {
            ec.clear();
            continue;
        }
        std::error_code type_error;
        if (it->is_regular_file(type_error) && !type_error && is_image(it->path()))
            images.push_back(it->path());
    }
    std::sort(images.begin(), images.end());
    return images;
}


bool daemon_running() {
    const pid_t pid = fork();
    if (pid < 0) return false;
    if (pid == 0) {
        const int nullfd = open("/dev/null", O_WRONLY);
        if (nullfd >= 0) {
            dup2(nullfd, STDOUT_FILENO);
            dup2(nullfd, STDERR_FILENO);
            close(nullfd);
        }
        execlp("pgrep", "pgrep", "-x", "awww-daemon", static_cast<char*>(nullptr));
        _exit(127);
    }

    int status = 0;
    while (waitpid(pid, &status, 0) < 0) {
        if (errno == EINTR) continue;
        return false;
    }
    return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

bool start_daemon_if_needed() {
    if (daemon_running()) {
        std::cout << "Wallshift: awww-daemon is already running.\\n";
        return true;
    }

    std::cout << "Wallshift: starting awww-daemon...\\n";
    const pid_t pid = fork();
    if (pid < 0) {
        std::cerr << "Error: could not fork to start awww-daemon.\\n";
        return false;
    }

    if (pid == 0) {
        if (setsid() < 0) _exit(1);

        const int nullfd = open("/dev/null", O_RDWR);
        if (nullfd >= 0) {
            dup2(nullfd, STDIN_FILENO);
            dup2(nullfd, STDOUT_FILENO);
            dup2(nullfd, STDERR_FILENO);
            if (nullfd > STDERR_FILENO) close(nullfd);
        }

        execlp("awww-daemon", "awww-daemon", static_cast<char*>(nullptr));
        _exit(127);
    }

    // Give the daemon time to initialize and verify that it actually stayed up.
    for (int attempt = 0; attempt < 20; ++attempt) {
        std::this_thread::sleep_for(std::chrono::milliseconds(250));
        if (daemon_running()) {
            std::cout << "Wallshift: awww-daemon started successfully.\\n";
            return true;
        }
    }

    std::cerr << "Error: could not start awww-daemon. Make sure 'awww-daemon' is installed "
                 "and your Wayland session environment is available.\\n";
    return false;
}

bool apply_wallpaper(const fs::path& image) {
    const pid_t pid = fork();
    if (pid < 0) {
        std::cerr << "Error: failed to start swww (fork failed).\n";
        return false;
    }
    if (pid == 0) {
        execlp("awww", "awww", "img", image.c_str(),
               "--transition-type", "any", static_cast<char*>(nullptr));
        std::cerr << "Error: could not execute 'awww'. Is awww installed?\n";
        _exit(127);
    }

    int status = 0;
    while (waitpid(pid, &status, 0) < 0) {
        if (errno == EINTR) continue;
        std::cerr << "Error: could not wait for swww.\n";
        return false;
    }
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        std::cerr << "Error: awww failed to apply the wallpaper. Is awww-daemon running?\n";
        return false;
    }
    return true;
}

int main(int argc, char** argv) {
    Options options;
    if (!parse_args(argc, argv, options)) return 2;
    if (options.help) {
        print_help(argv[0]);
        return 0;
    }

    std::error_code ec;
    fs::create_directories(options.directory, ec);
    if (ec) {
        std::cerr << "Error: cannot create wallpaper directory '"
                  << options.directory << "': " << ec.message() << '\n';
        return 1;
    }

    if (!start_daemon_if_needed()) return 1;

    std::mt19937 rng(std::random_device{}());
    std::vector<fs::path> images = find_images(options.directory);
    if (images.empty()) {
        std::cerr << "No supported image files found in: " << options.directory << '\n'
                  << "Add some images and run Wallshift again.\n";
        return 1;
    }

    std::size_t index = 0;
    if (options.random_mode) {
        std::uniform_int_distribution<std::size_t> pick(0, images.size() - 1);
        index = pick(rng);
    } else if (options.shuffle_mode) {
        std::shuffle(images.begin(), images.end(), rng);
    }

    std::cout << "Wallshift: " << images.size() << " image(s) found in "
              << options.directory << '\n';

    while (true) {
        if (options.random_mode) {
            std::uniform_int_distribution<std::size_t> pick(0, images.size() - 1);
            index = pick(rng);
        } else if (options.shuffle_mode && index >= images.size()) {
            auto refreshed = find_images(options.directory);
            if (!refreshed.empty()) images = std::move(refreshed);
            std::shuffle(images.begin(), images.end(), rng);
            index = 0;
        } else if (!options.shuffle_mode && !options.random_mode) {
            index %= images.size();
        }

        const fs::path selected = images[index];
        std::cout << "Setting wallpaper: " << selected << std::endl;
        if (!apply_wallpaper(selected)) return 1;

        if (options.once) return 0;
        std::this_thread::sleep_for(options.interval);

        if (!options.shuffle_mode) {
            // Refresh sequential/random modes so newly added images are picked up.
            auto refreshed = find_images(options.directory);
            if (!refreshed.empty()) {
                images = std::move(refreshed);
            } else {
                std::cerr << "Warning: no images currently found; keeping the last wallpaper.\n";
                continue;
            }
        }

        if (!options.random_mode) ++index;
    }
}

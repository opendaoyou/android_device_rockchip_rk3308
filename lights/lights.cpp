#define LOG_TAG "lights.rk3308"

#include <android-base/file.h>
#include <android-base/parseint.h>
#include <android-base/strings.h>
#include <android-base/unique_fd.h>
#include <hardware/lights.h>
#include <log/log.h>

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>

#include <new>
#include <string>

namespace {

constexpr char kBrightnessPath[] = "/sys/devices/platform/backlight/backlight/backlight/brightness";
constexpr char kMaxBrightnessPath[] =
        "/sys/devices/platform/backlight/backlight/backlight/max_brightness";

struct BacklightDevice {
    light_device_t light;
    int maxBrightness;
};

int SetBacklight(light_device_t* light, const light_state_t* state) {
    if (state->brightnessMode == BRIGHTNESS_MODE_LOW_PERSISTENCE) {
        return -ENOSYS;
    }

    const auto* device = reinterpret_cast<BacklightDevice*>(light);
    const unsigned int red = (state->color >> 16) & 0xff;
    const unsigned int green = (state->color >> 8) & 0xff;
    const unsigned int blue = state->color & 0xff;
    const unsigned int brightness = (77 * red + 150 * green + 29 * blue) >> 8;
    int level = (static_cast<uint64_t>(brightness) * device->maxBrightness + 127) / 255;
    if (brightness > 0 && level == 0) {
        level = 1;
    }

    android::base::unique_fd fd(TEMP_FAILURE_RETRY(open(kBrightnessPath, O_WRONLY | O_CLOEXEC)));
    if (fd.get() < 0) {
        const int error = errno;
        ALOGE("Cannot open backlight brightness: %s", strerror(error));
        return -error;
    }
    const std::string value = std::to_string(level) + "\n";
    const ssize_t written = TEMP_FAILURE_RETRY(write(fd.get(), value.data(), value.size()));
    if (written != static_cast<ssize_t>(value.size())) {
        const int error = written < 0 ? errno : EIO;
        ALOGE("Cannot set backlight brightness: %s", strerror(error));
        return -error;
    }
    return 0;
}

int CloseBacklight(hw_device_t* device) {
    delete reinterpret_cast<BacklightDevice*>(device);
    return 0;
}

int OpenLight(const hw_module_t* module, const char* name, hw_device_t** result) {
    if (strcmp(name, LIGHT_ID_BACKLIGHT) != 0) {
        return -EINVAL;
    }

    std::string value;
    if (!android::base::ReadFileToString(kMaxBrightnessPath, &value)) {
        const int error = errno;
        ALOGE("Cannot read maximum backlight brightness: %s", strerror(error));
        return -error;
    }
    int maxBrightness;
    if (!android::base::ParseInt(android::base::Trim(value), &maxBrightness, 1)) {
        ALOGE("Invalid maximum backlight brightness");
        return -EINVAL;
    }

    auto* device = new (std::nothrow) BacklightDevice{};
    if (device == nullptr) {
        return -ENOMEM;
    }
    device->maxBrightness = maxBrightness;
    device->light.common.tag = HARDWARE_DEVICE_TAG;
    device->light.common.version = LIGHTS_DEVICE_API_VERSION_2_0;
    device->light.common.module = const_cast<hw_module_t*>(module);
    device->light.common.close = CloseBacklight;
    device->light.set_light = SetBacklight;
    *result = &device->light.common;
    return 0;
}

hw_module_methods_t lightMethods = {
    .open = OpenLight,
};

}  // namespace

extern "C" {
hw_module_t HAL_MODULE_INFO_SYM = {
    .tag = HARDWARE_MODULE_TAG,
    .module_api_version = HARDWARE_MODULE_API_VERSION(1, 0),
    .hal_api_version = HARDWARE_HAL_API_VERSION,
    .id = LIGHTS_HARDWARE_MODULE_ID,
    .name = "Sogou E1 Backlight",
    .author = "Sogou E1 AOSP",
    .methods = &lightMethods,
};
}

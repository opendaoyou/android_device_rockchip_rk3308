LOCAL_PATH := $(call my-dir)

ifeq ($(TARGET_DEVICE),rk3308)
include $(CLEAR_VARS)
LOCAL_MODULE := lights.rk3308
LOCAL_MODULE_RELATIVE_PATH := hw
LOCAL_PROPRIETARY_MODULE := true
LOCAL_SRC_FILES := lights.cpp
LOCAL_SHARED_LIBRARIES := libbase libhardware liblog
LOCAL_CFLAGS := -Wall -Wextra -Werror
include $(BUILD_SHARED_LIBRARY)
endif

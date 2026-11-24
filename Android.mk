LOCAL_PATH := $(call my-dir)

ifeq ($(TARGET_DEVICE),rk3308)
ifneq ($(strip $(SOGOU_E1_RESOURCE)),)
$(PRODUCT_OUT)/boot.img $(PRODUCT_OUT)/recovery.img: $(SOGOU_E1_RESOURCE)
endif

include $(call all-makefiles-under,$(LOCAL_PATH))
endif

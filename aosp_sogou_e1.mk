$(call inherit-product, $(SRC_TARGET_DIR)/product/core_minimal.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/generic_no_telephony.mk)

PRODUCT_NAME := aosp_sogou_e1
PRODUCT_DEVICE := rk3308
PRODUCT_BRAND := Sogou
PRODUCT_MODEL := Sogou E1
PRODUCT_MANUFACTURER := Sogou
PRODUCT_CHARACTERISTICS := nosdcard

DEVICE_PACKAGE_OVERLAYS += device/rockchip/rk3308/overlay

PRODUCT_EXCLUDED_PACKAGES += \
    Camera2 \
    cameraserver \
    MmsService \
    Telecom \
    TelephonyProvider \
    TeleService

PRODUCT_COPY_FILES += \
    device/rockchip/rk3308/rootdir/fstab.rk3308:root/fstab.rk3308 \
    device/rockchip/rk3308/rootdir/init.rk3308.rc:root/init.rk3308.rc \
    device/rockchip/rk3308/rootdir/init.recovery.rk3308.rc:root/init.recovery.rk3308.rc \
    device/rockchip/rk3308/rootdir/ueventd.rk3308.rc:root/ueventd.rk3308.rc \
    device/rockchip/rk3308/rootdir/ueventd.vendor.rc:$(TARGET_COPY_OUT_VENDOR)/ueventd.rc \
    device/rockchip/rk3308/media_codecs.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs.xml \
    frameworks/av/media/libstagefright/data/media_codecs_google_audio.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_google_audio.xml \
    frameworks/av/media/libstagefright/data/media_codecs_google_video.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_google_video.xml \
    frameworks/native/data/etc/android.software.app_widgets.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.software.app_widgets.xml \
    device/rockchip/rk3308/firmware/rtl_bt/rtl8723d_fw.bin:$(TARGET_COPY_OUT_VENDOR)/etc/firmware/rtl_bt/rtl8723d_fw.bin \
    device/rockchip/rk3308/firmware/rtl_bt/rtl8723d_config.bin:$(TARGET_COPY_OUT_VENDOR)/etc/firmware/rtl_bt/rtl8723d_config.bin

ifneq ($(strip $(SOGOU_E1_KERNEL)),)
PRODUCT_COPY_FILES += $(SOGOU_E1_KERNEL):kernel
endif

# RK3308 has no GPU. Use the DRM driver's fbdev interface and software EGL.
PRODUCT_PACKAGES += \
    Launcher3SogouE1 \
    gralloc.default \
    lights.rk3308 \
    android.hardware.light@2.0-impl \
    android.hardware.light@2.0-service \
    android.hardware.graphics.allocator@2.0-impl \
    android.hardware.graphics.allocator@2.0-service \
    android.hardware.graphics.mapper@2.0-impl \
    android.hardware.configstore@1.0-service \
    android.hardware.keymaster@3.0-impl \
    android.hardware.keymaster@3.0-service \
    android.hardware.audio@2.0-impl \
    android.hardware.audio@2.0-service \
    android.hardware.audio.effect@2.0-impl \
    audio.primary.default \
    android.hardware.health@1.0-impl \
    android.hardware.power@1.0-impl \
    tinyplay \
    tinycap \
    tinymix

# Keep 320 dp of layout width on the panel for the standard Oreo UI.
PRODUCT_PROPERTY_OVERRIDES += \
    ro.product.locale=zh-CN \
    ro.config.low_ram=true \
    ro.config.software_canvas=true \
    ro.config.no_animations=true \
    config.disable_cameraservice=true \
    config.disable_telecom=true \
    ro.sf.lcd_density=160

ifneq ($(strip $(SOGOU_E1_MESA_DIR)),)
include device/rockchip/rk3308/mesa.mk
else
PRODUCT_PACKAGES += libEGL_swiftshader libGLESv1_CM_swiftshader libGLESv2_swiftshader
PRODUCT_PROPERTY_OVERRIDES += ro.hardware.egl=swiftshader
endif

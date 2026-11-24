# ARMv7 libraries staged by build-mesa.sh, with Android loader SONAMEs.
sogou_mesa_egl_libs := egl/libEGL_lp.so egl/libGLESv1_CM_lp.so egl/libGLESv2_lp.so
sogou_mesa_libs := $(sogou_mesa_egl_libs) egl/libgallium_dri.so
sogou_missing_mesa := $(filter-out $(wildcard $(addprefix $(SOGOU_E1_MESA_DIR)/,$(sogou_mesa_libs))),\
    $(addprefix $(SOGOU_E1_MESA_DIR)/,$(sogou_mesa_libs)))
ifneq ($(strip $(sogou_missing_mesa)),)
$(error Incomplete SOGOU_E1_MESA_DIR: $(sogou_missing_mesa))
endif

PRODUCT_COPY_FILES += \
    $(foreach lib,$(sogou_mesa_egl_libs),$(SOGOU_E1_MESA_DIR)/$(lib):vendor/lib/$(lib)) \
    $(SOGOU_E1_MESA_DIR)/egl/libgallium_dri.so:vendor/lib/libgallium_dri.so
ifneq ($(wildcard $(SOGOU_E1_MESA_DIR)/libglapi.so),)
PRODUCT_COPY_FILES += $(SOGOU_E1_MESA_DIR)/libglapi.so:vendor/lib/libglapi.so
endif
ifneq ($(wildcard $(SOGOU_E1_MESA_DIR)/hw/vulkan.rk3308.so),)
PRODUCT_COPY_FILES += $(SOGOU_E1_MESA_DIR)/hw/vulkan.rk3308.so:vendor/lib/hw/vulkan.rk3308.so
endif
PRODUCT_PROPERTY_OVERRIDES += \
    ro.hardware.egl=lp \
    mesa.libgl.always.software=true \
    mesa.android.no.kms.swrast=true

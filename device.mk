$(call inherit-product, device/qcom/msm8974/msm8974.mk)

PRODUCT_COPY_FILES := @inherit:device/qcom/common/common.mk

$(call inherit-product, $(SRC_TARGET_DIR)/product/generic.mk)

PRODUCT_COPY_FILES += \
  $(LOCAL_PATH)/rootdir/init.rc:root/init.rc \

PRODUCT_COPY_FILES += \
  $(LOCAL_PATH)/volume.cfg:system/etc/volume.cfg \
  $(LOCAL_PATH)/media_profiles.xml:system/etc/media_profiles.xml \
  $(LOCAL_PATH)/hostapd.conf:system/etc/hostapd/hostapd_default.conf \
  hardware/sony/timekeep/gecko/TimeKeepService.js:system/b2g/distribution/bundles/timekeep/TimeKeepService.js \
  hardware/sony/timekeep/gecko/chrome.manifest:system/b2g/distribution/bundles/timekeep/chrome.manifest \
  $(LOCAL_PATH)/nfc/libnfc-brcm.conf:system/etc/libnfc-brcm.conf \
  $(LOCAL_PATH)/nfc/libnfc-nxp.conf:system/etc/libnfc-nxp.conf \
  system/bluetooth/data/main.le.conf:system/etc/bluetooth/main.conf \

PRODUCT_DEFAULT_PROPERTY_OVERRIDES += \
  persist.sys.usb.config=mass_storage \
  ro.adb.secure=0 \

PRODUCT_PROPERTY_OVERRIDES += \
  ro.moz.nfc.enabled=true \
  ro.moz.bluetooth.backend=bluetoothd \
  ro.moz.ril.signal_extra_int=true \
  ro.moz.ril.avlbl_nw_extra_str=true \

PRODUCT_PACKAGES += \
  bcm4339.ko  \
  fakebattery \
  libandroid  \
  librecovery \
  nfcd        \
  rilproxy    \
  init.sh     \
  timekeep    \
  nfc_nci.pn54x.default \

# Needed to make sure bug 1177411 cannot resurface
export FOTA_DEVICE_DATA_FILES := /data/misc/dhcp/dhcpcd-wlan0.lease

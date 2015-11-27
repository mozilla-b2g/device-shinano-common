#!/bin/bash

# Copyright (C) 2010 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

if [ -z "${DEVICE}" ]; then
    echo "You need to define the DEVICE."
    exit 1
fi;

if [ -z "${MANUFACTURER}" ]; then
    echo "You need to define the MANUFACTURER."
    exit 1
fi;

if [[ -z "${ANDROIDFS_DIR}" ]]; then
    ANDROIDFS_DIR=../../../backup-${DEVICE}
fi

ROOT_FILES="
	charger
	default.prop
	file_contexts
	fstab.qcom
	init
	init.class_main.sh
	init.environ.rc
	init.mdm.sh
	init.qcom.class_core.sh
	init.qcom.early_boot.sh
	init.qcom.factory.sh
	init.qcom.rc
	init.qcom.sh
	init.qcom.ssr.sh
	init.qcom.syspart_fixup.sh
	init.rc
	init.sony-device-common.rc
	init.sony-device.rc
	init.sony-platform.rc
	init.sony.rc
	init.sony.usb.rc
	init.target.rc
	init.trace.rc
	init.usb.rc
	init.usbmode.sh
	logo.rle
	property_contexts
	seapp_contexts
	sepolicy
	ueventd.qcom.rc
	ueventd.rc
	"

if [[ ! -d ../../../backup-${DEVICE}/root/sbin ]]; then
    echo Backing up system partition to backup-${DEVICE}
    mkdir -p ../../../backup-${DEVICE}/root &&
    adb root &&
    sleep 1 &&
    adb wait-for-device &&
    adb pull /system ../../../backup-${DEVICE}/system &&
    echo Backing up root fs files to backup-${DEVICE} &&
    for NAME in $ROOT_FILES
    do
        adb pull /$NAME ../../../backup-${DEVICE}/root/
    done &&
    adb pull /res ../../../backup-${DEVICE}/root/res/ &&
    adb pull /sbin ../../../backup-${DEVICE}/root/sbin/
fi

echo Pulling files from ${ANDROIDFS_DIR}
DEVICE_BUILD_ID=`cat ${ANDROIDFS_DIR}/system/build.prop | grep ro.build.display.id | sed -e 's/ro.build.display.id=//' | tr -d '\n\r'`
DEVICE_BUILD_VERSION_SDK=`cat ${ANDROIDFS_DIR}/system/build.prop | grep ro.build.version.sdk | sed -e 's/ro.build.version.sdk=//' | tr -d '\n\r'`

if [[ "${DEVICE_BUILD_ID}" != "23.0.1.A.5.77" ]]; then
    echo Invalid system backup - Wrong base version found: ${DEVICE_BUILD_ID}.
    echo
    echo Do this:
    echo 1. Delete backup-${DEVICE}
    echo 2. Flash your device with KK based images from the vendor
    echo 3. Try building again
    exit -1
fi

BASE_PROPRIETARY_DEVICE_DIR=vendor/$MANUFACTURER/$DEVICE/proprietary
PROPRIETARY_DEVICE_DIR=../../../vendor/$MANUFACTURER/$DEVICE/proprietary

mkdir -p $PROPRIETARY_DEVICE_DIR

for NAME in audio etc etc/acdbdata/Fluid etc/acdbdata/Liquid etc/acdbdata/MTP etc/dhcpcd/dhcpcd-hooks etc/firmware egl hw nfc camera/LGI02BN1 camera/SEM02BN1 camera/SOI20BS1 root chargemon_data
do
    mkdir -p $PROPRIETARY_DEVICE_DIR/$NAME
done

BLOBS_LIST=../../../vendor/$MANUFACTURER/$DEVICE/$DEVICE-vendor-blobs.mk

(cat << EOF) | sed s/__DEVICE__/$DEVICE/g | sed s/__MANUFACTURER__/$MANUFACTURER/g > ../../../vendor/$MANUFACTURER/$DEVICE/$DEVICE-vendor-blobs.mk
# Copyright (C) 2010 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Prebuilt libraries that are needed to build open-source libraries
PRODUCT_COPY_FILES :=

# All the blobs
PRODUCT_COPY_FILES += \\
EOF

# copy_file
# pull file from the device and adds the file to the list of blobs
#
# $1 = src/dst name
# $2 = directory path on device
# $3 = directory name in $PROPRIETARY_DEVICE_DIR
copy_file()
{
    echo Pulling \"$1\"
    if [[ -z "${ANDROIDFS_DIR}" ]]; then
        NAME=$1
        adb pull /$2/$1 $PROPRIETARY_DEVICE_DIR/$3/$2
    else
        NAME=`basename ${ANDROIDFS_DIR}/$2/$1`
        rm -f $PROPRIETARY_DEVICE_DIR/$3/$NAME
        cp ${ANDROIDFS_DIR}/$2/$NAME $PROPRIETARY_DEVICE_DIR/$3/$NAME
    fi

    if [[ -f $PROPRIETARY_DEVICE_DIR/$3/$NAME ]]; then
        echo   $BASE_PROPRIETARY_DEVICE_DIR/$3/$NAME:$2/$NAME \\ >> $BLOBS_LIST
    else
        echo Failed to pull $1. Giving up.
        exit -1
    fi
}

# copy_files
# pulls a list of files from the device and adds the files to the list of blobs
#
# $1 = list of files
# $2 = directory path on device
# $3 = directory name in $PROPRIETARY_DEVICE_DIR
copy_files()
{
    for NAME in $1
    do
        copy_file "$NAME" "$2" "$3"
    done
}

# copy_files_glob
# pulls a list of files matching a pattern from the device and
# adds the files to the list of blobs
#
# $1 = pattern/glob
# $2 = directory path on device
# $3 = directory name in $PROPRIETARY_DEVICE_DIR
# $4 = list of files to exclude
copy_files_glob()
{
    DEVICE_PATH=$2
    BLOB_PATH=$3

    EXCLUDED=""
    if [ ! -z "$4" ]; then
        for EXCL in $4
        do
            echo "Excluding $EXCL"
            EXCLUDED="$EXCLUDED -not -name ${EXCL}"
        done
    fi;

    for NAME in $(find "${ANDROIDFS_DIR}/${DEVICE_PATH}/" -maxdepth 1 -type f -name "$1" ${EXCLUDED})
    do
        copy_file "`basename $NAME`" "${DEVICE_PATH}" "${BLOB_PATH}"
    done
}

# copy_local_files
# puts files in this directory on the list of blobs to install
#
# $1 = list of files
# $2 = directory path on device
# $3 = local directory path
copy_local_files()
{
    for NAME in $1
    do
        echo Adding \"$NAME\"
        echo device/$MANUFACTURER/$DEVICE/$3/$NAME:$2/$NAME \\ >> $BLOBS_LIST
    done
}

COMMON_ROOT="
	charger
	fstab.qcom
	init
	init.qcom.rc
	init.sony-device-common.rc
	init.sony-device.rc
	init.sony-platform.rc
	init.sony.rc
	init.sony.usb.rc
	init.target.rc
	init.usbmode.sh
	ueventd.qcom.rc
	"

COMMON_ROOT_SBIN="
	tad_static
	wait4tad_static
	"

copy_files "$COMMON_ROOT" "root" "root"
copy_files "$COMMON_ROOT_SBIN" "root/sbin" "root"
copy_files_glob "*.png" "root/res/images/charger" "root"

COMMON_LIBS="
	libnfc_ndef.so
	libcnefeatureconfig.so
	libgps.utils.so
	libloc_api_v02.so
	libloc_core.so
	libloc_ds_api.so
	libloc_eng.so
	libloc_xtra.so
	libmmcamera_interface.so
	libmmjpeg_interface.so
	libqomx_core.so
	libpin-cache.so
	libstartup-reason.so
	libkeyctrl.so
	libcald_client.so
	libcald_server.so
	libcald_pal.so
	libcald_util.so
	libexcal_core.so
	libcacao_common.so
	libcacao_pal.so
	libcammw.so
	libcameralight.so
	libexcal_system.so
	libcacao_system.so
	libcacao_parammgr.so
	libcacao_chokoball.so
	libcacao_client.so
	libcacao_face.so
	libcacao_imageconv.so
	libcacao_imgproc.so
	libcacao_jpeg.so
	libcacao_service.so
	libsony_face.so
	libsony_chokoballrsc.so
	libsomc_chokoballpal.so
	libsony_chokoball.so
	libidd.so
	libprotobuf-c.so
	libta.so
	libmiscta.so
	libcamera_clientsemc.so
	libxml2.so
	libtinyalsa.so
	libaudioroute.so
	libhardware_legacy.so
	libsonydseehxwrapper.so
	libcredential-manager-keystore.so
	libcredential-manager-service.so
	lib_asb_tee.so
	lib_get_secure_mode.so
	lib_get_rooting_status.so
	liblights-core.so
	libsys-utils.so
	libEffectOmxCore.so
	libdtcpipplayer.so
	libsapporo.so
	libaudiospring.so
	libaudioflinger.so
	libmedia.so
	libdisplayservice.so
	libsomc_thermal.so
	libreference-ril.so
	librilutils.so
	libril.so
	"

copy_files "$COMMON_LIBS" "system/lib" ""

COMMON_SOUNDFX_LIBS="
	libsweffectwrapper.so
	libvpt51wrapper.so
	"
copy_files "$COMMON_SOUNDFX_LIBS" "system/lib/soundfx" "audio"

copy_files_glob "*.so" "system/lib/camera" "camera"
copy_files_glob "*.dat" "system/vendor/camera" "camera"
copy_files_glob "*.dat" "system/vendor/camera/LGI02BN1" "camera/LGI02BN1"
copy_files_glob "*.dat" "system/vendor/camera/SEM02BN1" "camera/SEM02BN1"
copy_files_glob "*.dat" "system/vendor/camera/SOI20BS1" "camera/SOI20BS1"

copy_files "effect_init_params" "system/vendor/etc" "audio"

copy_files_glob "*.so" "system/vendor/lib/rfsa/adsp" "audio"
copy_files_glob "*.so" "system/vendor/lib/soundfx" "audio"

COMMON_VENDOR_LIBS_EXCLUDED="
	libwvm.so
	libExtendedExtractor.so
	"

copy_files_glob "lib*.so" "system/vendor/lib" "" "$COMMON_VENDOR_LIBS_EXCLUDED"

copy_files_glob "*.png" "system/somc/chargemon/data/msg" "chargemon_data"
copy_files_glob "*.png" "system/somc/chargemon/data/num" "chargemon_data"
copy_files_glob "*.png" "system/somc/chargemon/data/scale" "chargemon_data"

COMMON_BINS="
	adsprpcd
	bridgemgrd
	charger_monitor
	fm_qsoc_patches
	fmconfig
	hci_qcomm_init
	location-mq
	lowi-server
	mm-qcamera-daemon
	mpdecision
	netmgrd
	port-bridge
	ptt_socket_app
	qcom-system-daemon
	qmiproxy
	qmuxd
	qrngd
	qrngp
	qseecomd
	radish
	rfs_access
	rmt_storage
	sensors.qcom
	xtwifi-client
	xtwifi-inet-agent
	iddd
	imsdatadaemon
	imsqmidaemon
	ims_rtp_daemon
	idd-logreader
	irsc_util
	updatemiscta
	ta_qmi_service
	ta_param_loader
	mlog_qmi_service
	ssrapp
	ssr_diag
	sct_service
	suntrold
	illumination_service
	mediaserver
	scd
	credmgrd
	mm-pp-daemon
	gsiff_daemon
	hvdcp
	display_color_calib
	chargemon
	clearpad_fwloader
	taimport
	"

copy_files "$COMMON_BINS" "system/bin" ""


COMMON_HW="
	audio.primary.msm8974.so
	audio_policy.msm8974.so
	camera.qcom.so
	gps.default.so
	keystore.qcom.so
	lights.default.so
	libdisplay.default.so
	"
copy_files "$COMMON_HW" "system/lib/hw" "hw"

COMMON_ETC="
	ad_calib.cfg
	audio_effects.conf
	audio_policy.conf
	gps.conf
	lowi.conf
	media_codecs.xml
	mixer_paths.xml
	mixer_paths_auxpcm.xml
	xtwifi.conf
	flashled_calc_parameters.cfg
	iddd.conf
	dsx_param_file.bin
	sap.conf
	sec_config
	sensor_def_qcomdev.conf
	ramdump_ssr.xml
	pre_hw_config.sh
	"
copy_files "$COMMON_ETC" "system/etc" "etc"

copy_files_glob "*" "system/etc/tfa98xx" "audio"
copy_files_glob "*.bin" "system/etc/sforce" "audio"

COMMON_ETC_ACDBDATA_Fluid="
	Fluid_Bluetooth_cal.acdb
	Fluid_General_cal.acdb
	Fluid_Global_cal.acdb
	Fluid_Handset_cal.acdb
	Fluid_Hdmi_cal.acdb
	Fluid_Headset_cal.acdb
	Fluid_Speaker_cal.acdb
	"

copy_files "$COMMON_ETC_ACDBDATA_Fluid" "system/etc/acdbdata/Fluid" "etc/acdbdata/Fluid"

COMMON_ETC_ACDBDATA_Liquid="
	Liquid_Bluetooth_cal.acdb
	Liquid_General_cal.acdb
	Liquid_Global_cal.acdb
	Liquid_Handset_cal.acdb
	Liquid_Hdmi_cal.acdb
	Liquid_Headset_cal.acdb
	Liquid_Speaker_cal.acdb
	"

copy_files "$COMMON_ETC_ACDBDATA_Liquid" "system/etc/acdbdata/Liquid" "etc/acdbdata/Liquid"

COMMON_ETC_ACDBDATA_MTP="
	MTP_Bluetooth_cal.acdb
	MTP_General_cal.acdb
	MTP_Global_cal.acdb
	MTP_Handset_cal.acdb
	MTP_Hdmi_cal.acdb
	MTP_Headset_cal.acdb
	MTP_Speaker_cal.acdb
	"

copy_files "$COMMON_ETC_ACDBDATA_MTP" "system/etc/acdbdata/MTP" "etc/acdbdata/MTP"

COMMON_ETC_DHCPCD_DHCPCDHOOKS="
        95-configured
        "

copy_files "$COMMON_ETC_DHCPCD_DHCPCDHOOKS" "system/etc/dhcpcd/dhcpcd-hooks" "etc/dhcpcd/dhcpcd-hooks"

COMMON_IDC=clearpad.idc

copy_files "$COMMON_IDC" "system/usr/idc" "hw"

COMMON_AUDIO="
	"
#copy_files "$COMMON_AUDIO" "system/lib" "audio"

COMMON_EGL="
	libGLES_android.so
	"
copy_files "$COMMON_EGL" "system/lib/egl" "egl"

COMMON_VENDOR_NFC="
	libpn547_fw.so
	"
copy_files "$COMMON_VENDOR_NFC" "system/vendor/firmware" "nfc"

COMMON_VENDOR_EGL="
	eglsubAndroid.so
	libEGL_adreno.so
	libGLESv1_CM_adreno.so
	libGLESv2_adreno.so
	libq3dtools_adreno.so
	"
copy_files "$COMMON_VENDOR_EGL" "system/vendor/lib/egl" "egl"

COMMON_VENDOR_HW="
	flp.default.so
	power.qcom.so
	sensors.msm8974.so
        "
copy_files "$COMMON_VENDOR_HW" "system/vendor/lib/hw" "hw"

COMMON_FIRMWARE="
	a330_pfp.fw
	a330_pm4.fw
	adsp.b00
	adsp.b01
	adsp.b02
	adsp.b03
	adsp.b04
	adsp.b05
	adsp.b06
	adsp.b07
	adsp.b08
	adsp.b09
	adsp.b10
	adsp.b11
	adsp.b12
	adsp.mdt
	BCM43xx.hcd
	cmnlib.b00
	cmnlib.b01
	cmnlib.b02
	cmnlib.b03
	cmnlib.flist
	cmnlib.mdt
	cpp_firmware_v1_2_0.fw
	mba.b00
	mba.mdt
	modem.b00
	modem.b01
	modem.b02
	modem.b03
	modem.b06
	modem.b08
	modem.b09
	modem.b11
	modem.b12
	modem.b13
	modem.b14
	modem.b15
	modem.b16
	modem.b17
	modem.b18
	modem.b19
	modem.b22
	modem.b23
	modem.b24
	modem.b25
	modem.mdt
	tzhdcp.b00
	tzhdcp.b01
	tzhdcp.b02
	tzhdcp.b03
	tzhdcp.flist
	tzhdcp.mdt
	tzlibasb.b00
	tzlibasb.b01
	tzlibasb.b02
	tzlibasb.b03
	tzlibasb.flist
	tzlibasb.mdt
	tznautilus.b00
	tznautilus.b01
	tznautilus.b02
	tznautilus.b03
	tznautilus.flist
	tznautilus.mdt
	tzsuntory.b00
	tzsuntory.b01
	tzsuntory.b02
	tzsuntory.b03
	tzsuntory.flist
	tzsuntory.mdt
	tzwidevine.b00
	tzwidevine.b01
	tzwidevine.b02
	tzwidevine.b03
	tzwidevine.mdt
	venus.b00
	venus.b01
	venus.b02
	venus.b03
	venus.b04
	venus.mbn
	venus.mdt
	"
copy_files "$COMMON_FIRMWARE" "system/etc/firmware" "etc/firmware"

copy_files_glob "*.bin" "system/etc/firmware/wcd9320" "audio"
copy_files_glob "*" "system/etc/firmware/wlan/bcmdhd" "etc/firmware"

COMMON_VENDOR_FIRMWARE="
	keymaster.b00
	keymaster.b01
	keymaster.b02
	keymaster.b03
	keymaster.flist
	keymaster.mdt
	"

copy_files "$COMMON_VENDOR_FIRMWARE" "system/vendor/firmware/keymaster" "etc/firmware"

echo $BASE_PROPRIETARY_DEVICE_DIR/libcnefeatureconfig.so:obj/lib/libcnefeatureconfig.so \\ >> $BLOBS_LIST
echo $BASE_PROPRIETARY_DEVICE_DIR/hw/lights.default.so:system/lib/hw/lights.msm8974.so \\ >> $BLOBS_LIST


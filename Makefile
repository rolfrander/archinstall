
ARCH_MIRROR := https://mirror.archlinux.no/iso/latest/
ARCH        := archlinux-x86_64.iso
ARCH_SIG    := ${ARCH}.sig
ARCH_CIDATA := archlinux-cidata.iso
USB_DISKS   := $(filter-out %-part1 %-part2 %-part3,$(wildcard /dev/disk/by-id/usb*))
USB_DISK := $(if $(filter 1,$(words $(USB_DISKS))),$(firstword $(USB_DISKS)))

default: ${ARCH_CIDATA}
ifdef USB_DISK
	@echo "Run 'make install' to create USB on ${USB_DISK}"
else
	@echo "Assumes there is exactly one USB-disk attached, found: ${USB_DISKS}"
endif

install:
ifndef USB_DISK
	$(error Expected exactly one USB disk, found: $(USB_DISKS))
endif
	@dev=$$(readlink -f $(USB_DISK)); \
	if lsblk -nrpo MOUNTPOINT $$dev | grep -q .; \
	then echo "$$dev has mounted filesystems"  ; \
	else sudo dd if=${ARCH_CIDATA} of=$(USB_DISK) bs=4M status=progress oflag=sync ; \
	fi
	

FORCE:

${ARCH} ${ARCH_SIG} b2sums.txt: FORCE
	curl -s -o "$@" -z "$@" "${ARCH_MIRROR}/$@"

release-key:
	gpg --auto-key-locate clear,wkd -v --locate-key pierre@archlinux.org


.download-stamp: ${ARCH} ${ARCH_SIG} b2sums.txt release-key
	@if [ "$$(stat -c %Y ${ARCH})" != "$$(cat $@ 2>/dev/null || echo 0)" ]; then \
		stat -c %Y ${ARCH} > $@; \
	fi

download: .download-stamp
	b2sum --ignore-missing -c b2sums.txt
	gpg --verify ${ARCH_SIG} ${ARCH}

cloud-init/user-data: user-data.template .env user-data.pl
	./user-data.pl .env user-data.template > $@


cloud-init.img: cloud-init/*
	rm -f $@
	mkfs.fat -C -n CIDATA $@ 2048
	mcopy -i cloud-init.img cloud-init/* ::

${ARCH_CIDATA}: .download-stamp cloud-init.img
	rm -f $@
	xorriso -indev ${ARCH} \
	        -outdev ${ARCH_CIDATA} \
			-append_partition 3 0x0c cloud-init.img \
			-boot_image any replay


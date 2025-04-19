MKFILE_PATH := $(abspath $(lastword $(MAKEFILE_LIST)))
ROOT_DIR := $(abspath ${MKFILE_PATH}/..)

SHELL:=/bin/bash
GODOT:=/media/data/tmp_persistent/apps/godot/godot

.ONESHELL:
.PHONY: build push run

BUILD_TARGET_RPI:=build/godot-shrimp.arm64
BUILD_TARGET_STEAMDECK:=build/godot-shrimp.x86_64

steamdeck_setup:
	# have the deck user have a password with `passwd`
	ssh deck@192.168.0.173 sudo systemctl enable avahi-daemon && sudo systemctl start avahi-daemon

build_client:
	$(GODOT) --headless --verbose --export-debug "goshrimp-steamdeck" $(BUILD_TARGET_STEAMDECK)
	stat $(BUILD_TARGET_STEAMDECK)
build_server:
	$(GODOT) --headless --verbose --export-debug "goshrimp-rpi" $(BUILD_TARGET_RPI)
	stat $(BUILD_TARGET_RPI)
build:
	$(GODOT) --headless --verbose --export-debug "goshrimp-steamdeck" $(BUILD_TARGET_STEAMDECK)
	SERVER_PID=$$!
	$(GODOT) --headless --verbose --export-debug "goshrimp-rpi" $(BUILD_TARGET_RPI)
	CLIENT_PID=$$!
	wait $$SERVER_PID $$CLIENT_PID
	stat $(BUILD_TARGET_STEAMDECK)
	stat $(BUILD_TARGET_RPI)

push_server:
	rsync -P $(BUILD_TARGET_RPI) onze@goshrimp.local:/home/onze/goshrimp
push_client:
	rsync -P $(BUILD_TARGET_STEAMDECK) deck@steamdeck.local:/home/deck/goshrimp
push:
	rsync -P $(BUILD_TARGET_STEAMDECK) deck@steamdeck.local:/home/deck/goshrimp
	SERVER_PID=$$!
	rsync -P $(BUILD_TARGET_RPI) onze@goshrimp.local:/home/onze/goshrimp
	CLIENT_PID=$$!
	wait $$SERVER_PID $$CLIENT_PID


run_server:
	ssh -Xt onze@goshrimp.local /home/onze/goshrimp --headless -- --server --preset=rpi2desktop $(ARGS)

define CLIENT_SCRIPT:=


endef

run_client:
	echo 'export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$$UID/bus' > /tmp/goshrimp.run
	echo 'systemd-run --user ./goshrimp -- --client --preset=rpi2steamdeck $(ARGS) 2> goshrimp.run.log' >> /tmp/goshrimp.run
	echo 'SERVICE_NAME=$$(cat goshrimp.run.log | grep -Eo 'run-[0-9.a-z]+')' >> /tmp/goshrimp.run
	echo 'trap "systemctl --user stop $$SERVICE_NAME && exit 0" INT' >> /tmp/goshrimp.run
	echo 'read' >> /tmp/goshrimp.run
	scp /tmp/goshrimp.run deck@steamdeck.local:goshrimp.run
	ssh -t deck@steamdeck.local bash goshrimp.run

run:
	xterm -e ssh -X onze@goshrimp.local /home/onze/goshrimp --headless -- --server --preset=rpi2steamdeck $(ARGS) &
	SERVER_PID=$$!
	make run_client
	wait $$SERVER_PID



clean:
	rm -f $(BUILD_TARGET)

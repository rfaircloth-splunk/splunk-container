SHELL := /bin/bash
IMAGE_VERSION ?= "latest"
NONQUOTE_IMAGE_VERSION := $(patsubst "%",%,$(IMAGE_VERSION))
DOCKER_BUILD_FLAGS ?=
# Set Splunk version/build parameters here to define downstream URLs and file names
SPLUNK_PRODUCT := splunk
SPLUNK_VERSION := 7.3.1
SPLUNK_BUILD := bd63e13aa157

ifeq ($(shell arch), s390x)
	SPLUNK_ARCH = s390x
else
	SPLUNK_ARCH = x86_64
endif

# Linux Splunk arguments
SPLUNK_LINUX_FILENAME ?= splunk-${SPLUNK_VERSION}-${SPLUNK_BUILD}-Linux-${SPLUNK_ARCH}.tgz
SPLUNK_LINUX_BUILD_URL ?= https://download.splunk.com/products/${SPLUNK_PRODUCT}/releases/${SPLUNK_VERSION}/linux/${SPLUNK_LINUX_FILENAME}
UF_LINUX_FILENAME ?= splunkforwarder-${SPLUNK_VERSION}-${SPLUNK_BUILD}-Linux-${SPLUNK_ARCH}.tgz
UF_LINUX_BUILD_URL ?= https://download.splunk.com/products/universalforwarder/releases/${SPLUNK_VERSION}/linux/${UF_LINUX_FILENAME}
# Windows Splunk arguments
SPLUNK_WIN_FILENAME ?= splunk-${SPLUNK_VERSION}-${SPLUNK_BUILD}-x64-release.msi
SPLUNK_WIN_BUILD_URL ?= https://download.splunk.com/products/${SPLUNK_PRODUCT}/releases/${SPLUNK_VERSION}/windows/${SPLUNK_WIN_FILENAME}
UF_WIN_FILENAME ?= splunkforwarder-${SPLUNK_VERSION}-${SPLUNK_BUILD}-x64-release.msi
UF_WIN_BUILD_URL ?= https://download.splunk.com/products/universalforwarder/releases/${SPLUNK_VERSION}/windows/${UF_WIN_FILENAME}

# Security Scanner Variables
SCANNER_DATE := `date +%Y-%m-%d`
SCANNER_DATE_YEST := `TZ=GMT+24 +%Y:%m:%d`
SCANNER_VERSION := v8
SCANNER_LOCALIP := $(shell ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | awk '{print $1}' | head -n 1)
SCANNER_IMAGES_TO_SCAN := splunk-debian-9 splunk-debian-10 splunk-centos-7 splunk-redhat-8 uf-debian-9 uf-debian-10 uf-centos-7 uf-redhat-8
CONTAINERS_TO_SAVE := splunk-debian-9 splunk-debian-10 splunk-centos-7 splunk-redhat-8 uf-debian-9 uf-debian-10 uf-centos-7 uf-redhat-8
ifeq ($(shell uname), Linux)
	SCANNER_FILE = clair-scanner_linux_amd64
else ifeq ($(shell uname), Darwin)
	SCANNER_FILE = clair-scanner_darwin_amd64
else
	SCANNER_FILE = clair-scanner_windows_amd64.exe
endif


.PHONY: tests interactive_tutorials

#all: splunk uf
all: minimal-redhat-8

splunk.tgz:
	wget -qO splunk.tgz ${SPLUNK_LINUX_BUILD_URL}
	wget -qO splunk.tgz.md5 ${SPLUNK_LINUX_BUILD_URL}.md5
	tar zxf splunk.tgz

minimal-redhat-8: splunk.tgz
	docker build ${DOCKER_BUILD_FLAGS} \
		-f Dockerfile \
		-t rfaircloth/splunkcontainer:${IMAGE_VERSION} .

setup_clair_scanner:
	mkdir clair-scanner-logs
	mkdir test-results/cucumber
	docker stop clair_db || true
	docker rm clair_db || true
	docker stop clair || true
	docker rm clair || true
	docker pull arminc/clair-db:${SCANNER_DATE} || docker pull arminc/clair-db:${SCANNER_DATE_YEST} || echo "WARNING: Failed to pull daily image, defaulting to latest" >> clair-scanner-logs/clair_setup_errors.log ; docker pull arminc/clair-db:latest
	docker run -d --name clair_db arminc/clair-db:${SCANNER_DATE} || docker run -d --name clair_db arminc/clair-db:${SCANNER_DATE_YEST} || docker run -d --name clair_db arminc/clair-db:latest
	docker run -p 6060:6060 --link clair_db:postgres -d --name clair --restart on-failure arminc/clair-local-scan:v2.0.6
	wget https://github.com/arminc/clair-scanner/releases/download/${SCANNER_VERSION}/${SCANNER_FILE}
	mv ${SCANNER_FILE} clair-scanner
	chmod +x clair-scanner
	echo "Waiting for clair daemon to start"
	retries=0 ; while( ! wget -T 10 -q -O /dev/null http://0.0.0.0:6060/v1/namespaces ) ; do sleep 1 ; echo -n "." ; if [ $$retries -eq 10 ] ; then echo " Timeout, aborting." ; exit 1 ; fi ; retries=$$(($$retries+1)) ; done
	echo "Daemon started."

run_clair_scan:
	$(foreach image,${SCANNER_IMAGES_TO_SCAN}, mkdir test-results/clair-scanner-${image}; ./clair-scanner -c http://0.0.0.0:6060 --ip ${SCANNER_LOCALIP} -r test-results/clair-scanner-${image}/results.json -l clair-scanner-logs/${image}.log -w clair-whitelist.yml ${image}:${NONQUOTE_IMAGE_VERSION} || true ; python clair_to_junit_parser.py test-results/clair-scanner-${image}/results.json --output test-results/clair-scanner-${image}/results.xml ; )

setup_and_run_clair: setup_clair_scanner run_clair_scan

clean:
	docker stop clair_db || true
	docker rm clair_db || true
	docker stop clair || true
	docker rm clair || true
	rm -rf .pytest_cache || true
	rm -rf clair-scanner || true
	rm -rf clair-scanner-logs || true
	rm -rf test-results/* || true
	docker rm -f ${TEST_IMAGE_NAME} || true
	docker system prune -f --volumes

clean_ansible:
	rm -rf splunk-ansible

dev_loop:
	SPLUNK_IMAGE="splunk-debian-10:latest" make sample-compose-down && sleep 15  &&  DOCKER_BUILD_FLAGS="--no-cache" make all && sleep 15 && SPLUNK_IMAGE="splunk-debian-10:latest" make sample-compose-up

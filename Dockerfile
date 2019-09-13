
# Copyright 2018 Splunk
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
FROM registry.access.redhat.com/ubi8/ubi-minimal:latest
LABEL maintainer="support@splunk.com"
#
COPY install.sh /install.sh
COPY EULA_Red_Hat_Universal_Base_Image_English_20190422.pdf /EULA_Red_Hat_Universal_Base_Image_English_20190422.pdf

RUN /install.sh && \
    rm -rf /install.sh && \
    groupadd -g 999  splunk && \
    useradd -r -u 999 -g  splunk splunk



COPY splunk /opt/splunk
RUN tar cvfz /opt/splunk/splunk_etc.tar.gz /opt/splunk/etc &&\
    rm -Rf /opt/splunk/etc/* && \
    mkdir /opt/splunk/var && \
    mkdir /opt/splunk/var/cache && \
    chown -R splunk:splunk /opt/splunk

COPY splunk-entrypoint.sh /usr/local/bin/

RUN ln -s usr/local/bin/splunk-entrypoint.sh && \
    bash -c "echo -e '\nsplunk\tALL=(ALL) NOPASSWD:/bin/chown splunk\:splunk /opt/splunk'" >> /etc/sudoers && \
    bash -c "echo -e '\nsplunk\tALL=(ALL) NOPASSWD:/bin/chown splunk\:splunk /opt/splunk/etc'" >> /etc/sudoers && \
    bash -c "echo -e '\nsplunk\tALL=(ALL) NOPASSWD:/bin/chown splunk\:splunk /opt/splunk/var'" >> /etc/sudoers && \
    bash -c "echo -e '\nsplunk\tALL=(ALL) NOPASSWD:/bin/update-ca-trust'" >> /etc/sudoers && \
    bash -c "echo -e '\nsplunk\tALL=(ALL) NOPASSWD:/bin/cp /opt/splunk/certmanager/ca.crt /usr/share/pki/ca-trust-source/anchors/certmanager.pem'" >> /etc/sudoers

ENV SPLUNK_HOME=/opt/splunk
USER splunk
ENTRYPOINT ["splunk-entrypoint.sh"]
CMD ["splunk"]
# Hanlon server
#
# VERSION 2.4.0

FROM ruby:2.2.1-wheezy
MAINTAINER Joseph Callen <jcpowermac@gmail.com>

# Install the required dependencies
RUN apt-get update -y \
	&& apt-get install -y libxml2 gettext libfuse-dev libattr1-dev git build-essential libssl-dev p7zip-full fuseiso ipmitool \
	&& mkdir -p /usr/src/wimlib-code \
	&& mkdir -p /home/hanlon \
	&& git clone git://git.code.sf.net/p/wimlib/code /usr/src/wimlib-code \
	&& git clone https://github.com/csc/Hanlon.git /home/hanlon \
	&& cd /usr/src/wimlib-code \
	&& ./bootstrap \
	&& ./configure --without-ntfs-3g --prefix=/usr \
	&& make -j"$(nproc)" \
	&& make install \
	&& apt-get purge -y --auto-remove \
	gettext \
	&& rm -Rf /usr/src/wimlib-code \
	&& apt-get -y autoremove \
    	&& apt-get -y clean \
    	&& rm -rf /tmp/* /var/tmp/* /var/lib/apt/lists/*

# We don't need gem docs
RUN echo "install: --no-rdoc --no-ri" > /etc/gemrc

RUN gem install bundle \
	&& cd /home/hanlon \
	&& bundle install --system

ENV TEST_MODE true
ENV LANG en_US.UTF-8
ENV WIMLIB_IMAGEX_USE_UTF8 true
ENV HANLON_WEB_PATH /home/hanlon/web

COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

WORKDIR /home/hanlon

ENTRYPOINT ["/docker-entrypoint.sh"]

# Hanlon by default runs at TCP 8026
EXPOSE 8026
CMD []

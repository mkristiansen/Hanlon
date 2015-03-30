# Hanlon server
#
# VERSION 2.3.0

FROM ruby:2.2-wheezy
MAINTAINER Joseph Callen <jcpowermac@gmail.com>

# Install the required dependencies
RUN apt-get update -y \
	&& apt-get install -y libxml2 gettext libfuse-dev libattr1-dev git build-essential libssl-dev p7zip-full fuseiso \
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

# Hanlon by default runs at TCP 8026
EXPOSE 8026

ENV TEST_MODE true
ENV LANG en_US.UTF-8
ENV WIMLIB_IMAGEX_USE_UTF8 true

WORKDIR /home/hanlon/web
CMD (cd /home/hanlon && ./hanlon_init -j '{"hanlon_static_path": "'$HANLON_STATIC_PATH'", "hanlon_subnets": "'$HANLON_SUBNETS'", "hanlon_server": "'$DOCKER_HOST'", "persist_host": "'$MONGO_PORT_27017_TCP_ADDR'"}' ) && ./run-puma.sh

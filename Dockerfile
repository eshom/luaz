FROM debian:bullseye

RUN apt update && \
        apt install -y clang make libreadline8
RUN mkdir -p /home/lua/out && mkdir -p /home/lua/tests
COPY tests /home/lua/tests

# Mount zig-out to dynamically use latest artifacts
VOLUME [ "/home/lua/out" ]

WORKDIR /home/lua/tests

RUN chmod 777 container_run.sh

# Runtime
ENTRYPOINT [ "./container_run.sh" ]
CMD [ "/usr/bin/bash" ]

# ENTRYPOINT [ "bash" ]


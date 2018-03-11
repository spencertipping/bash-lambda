FROM ubuntu:16.04
ADD bash-lambda /root/
RUN echo source /root/bash-lambda >> /root/.bashrc
CMD /bin/bash

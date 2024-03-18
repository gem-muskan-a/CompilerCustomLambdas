FROM public.ecr.aws/lambda/provided:al2.2022.12.02.19

RUN yum install java-21-openjdk-devel -y
RUN yum install jq -y
RUN yum install postgresql -y
RUN yum install time -y

COPY hello.sh /var/runtime/hello.sh
COPY bootstrap /var/runtime/bootstrap
RUN chmod +x /var/runtime/bootstrap

CMD ["hello.handler"]

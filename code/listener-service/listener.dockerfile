# Optimized with makefile
FROM alpine:latest
RUN mkdir /app
COPY listenerApp /app
CMD [ "/app/listenerApp" ]
# Optimized with makefile
FROM alpine:latest
RUN mkdir /app
COPY listenerApp /app
RUN addgroup -g 10999 appgroup && \
    adduser -D -u 10999 -G appgroup appuser
RUN chown -R appuser:appgroup /app
USER 10999:10999
CMD [ "/app/listenerApp" ]
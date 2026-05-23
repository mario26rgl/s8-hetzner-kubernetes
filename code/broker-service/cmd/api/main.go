package main

import (
	"fmt"
	"log"
	"math"
	"net/http"
	"os"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"
)

const webPort = "80"

type Config struct {
	amqpConnection *amqp.Connection
}

func main() {
	// connect to rabbitmq
	rabbitConn, err := connect()
	if err != nil {
		log.Panic(err)
	}
	defer rabbitConn.Close()

	app := Config{
		amqpConnection: rabbitConn,
	}

	log.Printf("Starting broker service on port %s\n", webPort)

	// define HTTP server
	srv := &http.Server{
		Addr:    fmt.Sprintf(":%s", webPort),
		Handler: app.routes(),
	}

	// start HTTP server
	err = srv.ListenAndServe()
	if err != nil {
		log.Panic(err)
	}
}

func connect() (*amqp.Connection, error) {
	var counts = 0
	var backOff = 1 * time.Second
	var connection *amqp.Connection
	rabbitMQURL := os.Getenv("RABBITMQ_URL")
	if rabbitMQURL == "" {
		rabbitMQURL = "amqp://user:password@rabbitmq.rabbitmq.svc.cluster.local:5672/"
	}

	for {
		c, err := amqp.Dial(rabbitMQURL)
		if err != nil {
			log.Printf("RabbitMQ not yet ready, retrying in %v seconds\n", backOff.Seconds())
			counts++
		} else {
			log.Println("Connected to RabbitMQ!")
			connection = c
			break
		}

		if counts >= 5 {
			log.Println("RabbitMQ connection failed after 5 attempts")
			return nil, err
		}

		backOff = time.Duration(math.Pow(2, float64(counts))) * time.Second
		time.Sleep(backOff)
		continue
	}

	return connection, nil
}

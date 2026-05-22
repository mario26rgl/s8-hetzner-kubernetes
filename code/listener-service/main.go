package main

import (
	"listener-service/event"
	"log"
	"math"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"
)

func main() {
	// connect to rabbitmq
	conn, err := connect()
	if err != nil {
		log.Panic(err)
	}
	defer conn.Close()

	// start listening for messages
	log.Println("Listening for and consuming RMQ messages...")

	// create consumer
	consumer, err := event.NewConsumer(conn)
	if err != nil {
		log.Panic(err)
	}

	// watch the queue and consume events
	err = consumer.Listen([]string{"log.INFO", "log.WARNING", "log.ERROR"})
	if err != nil {
		log.Panic(err)
	}
}

func connect() (*amqp.Connection, error) {
	var counts = 0
	var backOff = 1 * time.Second
	var connection *amqp.Connection

	for {
		c, err := amqp.Dial("amqp://user:password@rabbitmq:5672/")
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

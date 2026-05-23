package event

import (
	"bytes"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"net/rpc"
	"os"

	amqp "github.com/rabbitmq/amqp091-go"
)

type Consumer struct {
	conn      *amqp.Connection
	queueName string
}

func NewConsumer(conn *amqp.Connection) (Consumer, error) {

	consumer := Consumer{
		conn: conn,
	}

	err := consumer.setup()
	if err != nil {
		return Consumer{}, err
	}

	return consumer, nil
}

func (consumer *Consumer) setup() error {
	channel, err := consumer.conn.Channel()
	if err != nil {
		return err
	}

	return declareExchange(channel)
}

type Payload struct {
	Name string `json:"name"`
	Data string `json:"data"`
}

func (consumer *Consumer) Listen(topics []string) error {
	ch, err := consumer.conn.Channel()
	if err != nil {
		return err
	}
	defer ch.Close()

	q, err := declareRandomQueue(ch)
	if err != nil {
		return err
	}

	for _, topic := range topics {
		err = ch.QueueBind(
			q.Name,
			topic,
			"logs_topic",
			false,
			nil,
		)

		if err != nil {
			return err
		}
	}

	messages, err := ch.Consume(q.Name, "", true, false, false, false, nil)
	if err != nil {
		return err
	}

	forever := make(chan bool)
	go func() {
		for d := range messages {
			log.Printf("Received a message: %s", d.Body)
			var payload Payload
			_ = json.Unmarshal(d.Body, &payload)

			go handlePayload(payload)
		}
	}()

	log.Printf("Waiting for message [Exchange, Queue] [logs_topic, %s]", q.Name)
	<-forever

	return nil
}

func handlePayload(payload Payload) {
	switch payload.Name {
	case "log", "event":
		err := logEventViaRPC(payload)
		if err != nil {
			log.Printf("Error logging event: %v", err)
		}
	case "auth":
		// err := logAuth(payload)
		// if err != nil {
		// 	log.Printf("Error logging auth: %v", err)
		// }
	default:
		log.Printf("Unknown payload: %s with data: %s", payload.Name, payload.Data)
	}
}

func logEvent(entry Payload) error {
	// Implementation for logging item
	jsonData, _ := json.MarshalIndent(entry, "", "\t")
	loggerServiceURL := os.Getenv("LOGGER_SERVICE_URL")
	if loggerServiceURL == "" {
		loggerServiceURL = "http://logger-service.logger-service.svc.cluster.local"
	}

	request, err := http.NewRequest("POST", loggerServiceURL+"/log", bytes.NewBuffer(jsonData))
	if err != nil {
		return err
	}

	request.Header.Set("Content-Type", "application/json")

	client := &http.Client{}
	response, err := client.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()

	if response.StatusCode != http.StatusAccepted {
		return errors.New("error calling logger service")
	}

	return nil
}

type RPCPayload struct {
	Name string `json:"name"`
	Data string `json:"data"`
}

func logEventViaRPC(entry Payload) error {
	// Implementation for logging item via RPC
	loggerRPCAddress := os.Getenv("LOGGER_SERVICE_RPC_ADDR")
	if loggerRPCAddress == "" {
		loggerRPCAddress = "logger-service.logger-service.svc.cluster.local:5001"
	}

	client, err := rpc.Dial("tcp", loggerRPCAddress)
	if err != nil {
		return err
	}

	rpcPayload := RPCPayload{
		Name: entry.Name,
		Data: entry.Data,
	}

	var result string
	err = client.Call("RPCServer.LogInfo", rpcPayload, &result)
	if err != nil {
		return err
	}

	log.Printf("RPC response: %s", result)
	return nil
}

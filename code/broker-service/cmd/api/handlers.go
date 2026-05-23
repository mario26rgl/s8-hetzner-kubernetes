package main

import (
	"broker/event"
	"broker/logs"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

type jsonResponse struct {
	Error   bool   `json:"error"`
	Message string `json:"message"`
	Data    any    `json:"data,omitempty"`
}

type RequestPayload struct {
	Action string      `json:"action"`
	Auth   AuthPayload `json:"auth,omitempty"`
	Log    LogPayload  `json:"log,omitempty"`
	Mail   MailPayload `json:"mail,omitempty"`
}

type AuthPayload struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type LogPayload struct {
	Name string `json:"name"`
	Data string `json:"data"`
}

type MailPayload struct {
	From    string `json:"from"`
	To      string `json:"to"`
	Subject string `json:"subject"`
	Message string `json:"message"`
}

func (app *Config) Broker(w http.ResponseWriter, r *http.Request) {
	payload := jsonResponse{
		Error:   false,
		Message: "Hit the broker",
	}

	_ = app.writeJSON(w, http.StatusOK, payload)
}

func (app *Config) HandleSubmission(w http.ResponseWriter, r *http.Request) {
	var requestPayload RequestPayload

	err := app.readJSON(w, r, &requestPayload)
	if err != nil {
		app.errorJSON(w, err, http.StatusBadRequest)
		return
	}

	switch requestPayload.Action {
	case "auth":
		app.authenticate(w, requestPayload.Auth)
	case "log":
		app.logEventViaRabbit(w, requestPayload.Log)
	case "mail":
		app.sendMail(w, requestPayload.Mail)
	default:
		app.errorJSON(w, errors.New("unknown action"), http.StatusBadRequest)
	}
}

func (app *Config) authenticate(w http.ResponseWriter, a AuthPayload) {
	jsonData, _ := json.MarshalIndent(a, "", "\t")

	request, err := http.NewRequest("POST", "http://auth-service/authenticate", bytes.NewBuffer(jsonData))
	if err != nil {
		app.errorJSON(w, err)
		return
	}

	request.Header.Set("Content-Type", "application/json")

	client := &http.Client{}
	response, err := client.Do(request)
	if err != nil {
		app.errorJSON(w, err)
		return
	}
	defer response.Body.Close()

	if response.StatusCode == http.StatusUnauthorized {
		app.errorJSON(w, errors.New("invalid credentials"), http.StatusUnauthorized)
		return
	} else if response.StatusCode != http.StatusAccepted {
		app.errorJSON(w, errors.New("error calling auth service"))
		return
	}

	var jsonFromAuthService jsonResponse

	err = json.NewDecoder(response.Body).Decode(&jsonFromAuthService)
	if err != nil {
		app.errorJSON(w, err)
		return
	}

	if jsonFromAuthService.Error {
		app.errorJSON(w, errors.New(jsonFromAuthService.Message), http.StatusUnauthorized)
		return
	}

	var payload jsonResponse
	payload.Error = false
	payload.Message = "Authenticated!"
	payload.Data = jsonFromAuthService.Data
	app.writeJSON(w, http.StatusOK, payload)

}

func (app *Config) logItem(w http.ResponseWriter, l LogPayload) {
	// Implementation for logging item
	jsonData, _ := json.MarshalIndent(l, "", "\t")

	request, err := http.NewRequest("POST", "http://logger-service/log", bytes.NewBuffer(jsonData))
	if err != nil {
		app.errorJSON(w, err)
		return
	}

	request.Header.Set("Content-Type", "application/json")

	client := &http.Client{}
	response, err := client.Do(request)
	if err != nil {
		app.errorJSON(w, err)
		return
	}
	defer response.Body.Close()

	if response.StatusCode != http.StatusAccepted {
		app.errorJSON(w, errors.New("error calling logger service"))
		return
	}

	var payload jsonResponse
	payload.Error = false
	payload.Message = "Logged!"
	app.writeJSON(w, http.StatusOK, payload)
}

func (app *Config) sendMail(w http.ResponseWriter, m MailPayload) {
	// Implementation for sending mail
	jsonData, _ := json.MarshalIndent(m, "", "\t")

	request, err := http.NewRequest("POST", "http://mail-service/send", bytes.NewBuffer(jsonData))
	if err != nil {
		app.errorJSON(w, err)
		return
	}

	request.Header.Set("Content-Type", "application/json")

	client := &http.Client{}
	response, err := client.Do(request)
	if err != nil {
		app.errorJSON(w, err)
		return
	}
	defer response.Body.Close()

	if response.StatusCode != http.StatusAccepted {
		if response.StatusCode == http.StatusBadRequest {
			app.errorJSON(w, errors.New("error calling mail service: bad request"), http.StatusBadRequest)
			return
		} else {
			app.errorJSON(w, errors.New("error calling mail service: internal server error"), http.StatusInternalServerError)
			return
		}
	}

	var payload jsonResponse
	payload.Error = false
	payload.Message = "Mail sent!"
	app.writeJSON(w, http.StatusOK, payload)
}

func (app *Config) logEventViaRabbit(w http.ResponseWriter, l LogPayload) {
	err := app.pushToQueue(l)
	if err != nil {
		app.errorJSON(w, err)
		return
	}

	var payload jsonResponse
	payload.Error = false
	payload.Message = "Logged via RabbitMQ!"
	app.writeJSON(w, http.StatusAccepted, payload)
}

func (app *Config) pushToQueue(payload LogPayload) error {
	emitter, err := event.NewEventEmitter(app.amqpConnection)
	if err != nil {
		return err
	}

	jsonData, _ := json.MarshalIndent(payload, "", "\t")

	err = emitter.Push(string(jsonData), "INFO")
	if err != nil {
		return err
	}

	return nil
}

func (app *Config) logItemViaGRPC(w http.ResponseWriter, r *http.Request) {
	var requestPayload RequestPayload

	err := app.readJSON(w, r, &requestPayload)
	if err != nil {
		app.errorJSON(w, err, http.StatusBadRequest)
		return
	}

	conn, err := grpc.NewClient("logger-service:50051", grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		app.errorJSON(w, err)
		return
	}
	defer conn.Close()

	c := logs.NewLogServiceClient(conn)
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()

	_, err = c.WriteLog(ctx, &logs.LogRequest{
		LogEntry: &logs.Log{
			Name: requestPayload.Log.Name,
			Data: requestPayload.Log.Data,
		},
	})

	if err != nil {
		app.errorJSON(w, err)
		return
	}

	var payload jsonResponse
	payload.Error = false
	payload.Message = "Logged via gRPC"
	app.writeJSON(w, http.StatusAccepted, payload)
}

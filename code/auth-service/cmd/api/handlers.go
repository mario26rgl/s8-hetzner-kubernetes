package main

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"authentication/data"
)

type jsonResponse struct {
	Error   bool   `json:"error"`
	Message string `json:"message"`
	Data    any    `json:"data,omitempty"`
}

type authTokenPayload struct {
	Token string `json:"token"`
	User  any    `json:"user"`
}

const tokenTTL = 24 * time.Hour

func (app *Config) Authenticate(w http.ResponseWriter, r *http.Request) {
	var requestPayload struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}

	err := app.readJSON(w, r, &requestPayload)
	if err != nil {
		app.errorJSON(w, err, http.StatusBadRequest)
		return
	}

	user, err := app.Models.User.GetByEmail(requestPayload.Email)
	if err != nil {
		app.errorJSON(w, errors.New("invalid credentials"), http.StatusUnauthorized)
		return
	}

	valid, err := user.PasswordMatches(requestPayload.Password)
	if err != nil || !valid {
		err = app.logRequest("Auth log", fmt.Sprintf("User %s entered invalid credentials", user.Email))
		if err != nil {
			app.errorJSON(w, errors.New("failed to log authentication"), http.StatusInternalServerError)
			return
		}
		app.errorJSON(w, errors.New("invalid credentials"), http.StatusUnauthorized)
		return
	}

	token, err := generateAuthToken(user.ID)
	if err != nil {
		app.errorJSON(w, errors.New("failed to generate token"), http.StatusInternalServerError)
		return
	}

	// log successful authentication
	err = app.logRequest("Auth log", fmt.Sprintf("User %s authenticated successfully", user.Email))
	if err != nil {
		app.errorJSON(w, errors.New("failed to log authentication"), http.StatusInternalServerError)
		return
	}

	payload := jsonResponse{
		Error:   false,
		Message: fmt.Sprintf("Logged in user %s", user.Email),
		Data: authTokenPayload{
			Token: token,
			User:  user,
		},
	}

	app.writeJSON(w, http.StatusAccepted, payload)
}

func (app *Config) SignUp(w http.ResponseWriter, r *http.Request) {
	var requestPayload struct {
		Email     string `json:"email"`
		Password  string `json:"password"`
		FirstName string `json:"first_name"`
		LastName  string `json:"last_name"`
	}

	err := app.readJSON(w, r, &requestPayload)
	if err != nil {
		app.errorJSON(w, err, http.StatusBadRequest)
		return
	}

	if requestPayload.Email == "" || requestPayload.Password == "" {
		app.errorJSON(w, errors.New("email and password are required"), http.StatusBadRequest)
		return
	}

	existingUser, err := app.Models.User.GetByEmail(requestPayload.Email)
	if err == nil && existingUser != nil {
		app.errorJSON(w, errors.New("email already registered"), http.StatusConflict)
		return
	}
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		app.errorJSON(w, errors.New("failed to check user existence"), http.StatusInternalServerError)
		return
	}

	newUser := data.User{
		Email:     requestPayload.Email,
		Password:  requestPayload.Password,
		FirstName: requestPayload.FirstName,
		LastName:  requestPayload.LastName,
		Active:    1,
	}

	newID, err := app.Models.User.Insert(newUser)
	if err != nil {
		app.errorJSON(w, errors.New("failed to create user"), http.StatusInternalServerError)
		return
	}

	createdUser, err := app.Models.User.GetOne(newID)
	if err != nil {
		app.errorJSON(w, errors.New("failed to fetch created user"), http.StatusInternalServerError)
		return
	}

	token, err := generateAuthToken(createdUser.ID)
	if err != nil {
		app.errorJSON(w, errors.New("failed to generate token"), http.StatusInternalServerError)
		return
	}

	err = app.logRequest("Auth log", fmt.Sprintf("User %s signed up successfully", createdUser.Email))
	if err != nil {
		app.errorJSON(w, errors.New("failed to log sign up"), http.StatusInternalServerError)
		return
	}

	payload := jsonResponse{
		Error:   false,
		Message: fmt.Sprintf("Signed up user %s", createdUser.Email),
		Data: authTokenPayload{
			Token: token,
			User:  createdUser,
		},
	}

	app.writeJSON(w, http.StatusCreated, payload)
}

func (app *Config) Verify(w http.ResponseWriter, r *http.Request) {
	var requestPayload struct {
		Token string `json:"token"`
	}

	err := app.readJSON(w, r, &requestPayload)
	if err != nil {
		app.errorJSON(w, err, http.StatusBadRequest)
		return
	}

	userID, err := verifyAuthToken(requestPayload.Token)
	if err != nil {
		app.errorJSON(w, errors.New("invalid token"), http.StatusUnauthorized)
		return
	}

	user, err := app.Models.User.GetOne(userID)
	if err != nil {
		app.errorJSON(w, errors.New("user not found"), http.StatusUnauthorized)
		return
	}

	payload := jsonResponse{
		Error:   false,
		Message: "Token is valid",
		Data: authTokenPayload{
			Token: requestPayload.Token,
			User:  user,
		},
	}

	app.writeJSON(w, http.StatusAccepted, payload)
}

func (app *Config) logRequest(name, data string) error {
	// Implementation for logging requests
	var entry struct {
		Name string `json:"name"`
		Data string `json:"data"`
	}

	entry.Name = name
	entry.Data = data

	jsonData, _ := json.MarshalIndent(entry, "", "\t")

	request, err := http.NewRequest("POST", "http://logger-service/log", bytes.NewBuffer(jsonData))
	if err != nil {
		log.Printf("Error creating log request: %v", err)
		return err
	}

	request.Header.Set("Content-Type", "application/json")

	client := &http.Client{}
	_, err = client.Do(request)
	if err != nil {
		log.Printf("Error calling logger service: %v", err)
		return err
	}

	return nil
}

func generateAuthToken(userID int) (string, error) {
	expiresAt := time.Now().Add(tokenTTL).Unix()
	claims := fmt.Sprintf("%d:%d", userID, expiresAt)
	signature := authTokenSignature(claims)
	encoded := base64.StdEncoding.EncodeToString([]byte(claims + ":" + signature))

	return encoded, nil
}

func verifyAuthToken(token string) (int, error) {
	decoded, err := base64.StdEncoding.DecodeString(token)
	if err != nil {
		return 0, err
	}

	parts := strings.Split(string(decoded), ":")
	if len(parts) != 3 {
		return 0, errors.New("invalid token format")
	}

	userID, err := strconv.Atoi(parts[0])
	if err != nil {
		return 0, err
	}

	expiresAt, err := strconv.ParseInt(parts[1], 10, 64)
	if err != nil {
		return 0, err
	}

	if time.Now().Unix() > expiresAt {
		return 0, errors.New("token expired")
	}

	claims := parts[0] + ":" + parts[1]
	expectedSignature := authTokenSignature(claims)
	if !hmac.Equal([]byte(parts[2]), []byte(expectedSignature)) {
		return 0, errors.New("invalid token signature")
	}

	return userID, nil
}

func authTokenSignature(claims string) string {
	secret := os.Getenv("AUTH_TOKEN_SECRET")
	if secret == "" {
		secret = "development-auth-secret"
	}

	mac := hmac.New(sha256.New, []byte(secret))
	_, _ = mac.Write([]byte(claims))
	return fmt.Sprintf("%x", mac.Sum(nil))
}

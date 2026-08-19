package utils

import (
	"errors"
	"os"
	"strconv"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"go.mongodb.org/mongo-driver/bson/primitive"

	"articulate-go/internal/models"
)

var ErrInvalidToken = errors.New("invalid or expired token")

type Claims struct {
	UserID string      `json:"user_id"`
	Role   models.Role `json:"role"`
	jwt.RegisteredClaims
}

func jwtSecret() []byte {
	secret := os.Getenv("JWT_SECRET")
	if secret == "" {
		secret = "dev-insecure-secret-change-me"
	}
	return []byte(secret)
}

func tokenExpiry() time.Duration {
	hoursStr := os.Getenv("JWT_EXPIRY_HOURS")
	if hoursStr == "" {
		return 24 * time.Hour
	}
	hours, err := strconv.Atoi(hoursStr)
	if err != nil || hours <= 0 {
		return 24 * time.Hour
	}
	return time.Duration(hours) * time.Hour
}

func GenerateToken(userID primitive.ObjectID, role models.Role) (string, error) {
	now := time.Now()
	claims := Claims{
		UserID: userID.Hex(),
		Role:   role,
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   userID.Hex(),
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(tokenExpiry())),
			NotBefore: jwt.NewNumericDate(now),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(jwtSecret())
}

func ParseToken(tokenString string) (*Claims, error) {
	claims := &Claims{}

	token, err := jwt.ParseWithClaims(tokenString, claims, func(t *jwt.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, ErrInvalidToken
		}
		return jwtSecret(), nil
	})
	if err != nil || !token.Valid {
		return nil, ErrInvalidToken
	}

	return claims, nil
}
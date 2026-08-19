package models

import (
	"time"

	"go.mongodb.org/mongo-driver/bson/primitive"
)

type Role string

const (
	RoleAdmin     Role = "admin"
	RoleRecruiter Role = "recruiter"
	RoleEvaluator Role = "evaluator"
	RoleCandidate Role = "candidate"
)

type User struct {
	ID           primitive.ObjectID `bson:"_id,omitempty" json:"id"`
	Email        string             `bson:"email" json:"email"`
	PasswordHash string             `bson:"password_hash" json:"-"`
	FullName     string             `bson:"full_name" json:"full_name"`
	Role         Role               `bson:"role" json:"role"`
	Permissions  []string           `bson:"permissions,omitempty" json:"permissions,omitempty"`
	IsActive     bool               `bson:"is_active" json:"is_active"`
	LastLoginAt  *time.Time         `bson:"last_login_at,omitempty" json:"last_login_at,omitempty"`
	CreatedAt    time.Time          `bson:"created_at" json:"created_at"`
	UpdatedAt    time.Time          `bson:"updated_at" json:"updated_at"`
}
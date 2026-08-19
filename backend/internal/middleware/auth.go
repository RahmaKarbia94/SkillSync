package middleware

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"articulate-go/internal/models"
	"articulate-go/internal/utils"
)

const (
	ContextUserID = "userID"
	ContextRole   = "role"
)

func AuthRequired() gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "missing authorization header"})
			return
		}

		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid authorization header format"})
			return
		}

		claims, err := utils.ParseToken(parts[1])
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired token"})
			return
		}

		c.Set(ContextUserID, claims.UserID)
		c.Set(ContextRole, claims.Role)
		c.Next()
	}
}

func RequireRole(allowedRoles ...models.Role) gin.HandlerFunc {
	return func(c *gin.Context) {
		roleVal, exists := c.Get(ContextRole)
		if !exists {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "role not found in context"})
			return
		}

		role, ok := roleVal.(models.Role)
		if !ok {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "invalid role type"})
			return
		}

		for _, r := range allowedRoles {
			if r == role {
				c.Next()
				return
			}
		}

		c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "insufficient permissions"})
	}
}
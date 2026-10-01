// Package auth implements email/password accounts for the mobile app's built-in wallet. The
// backend never sees a usable private key: registration hands it a wallet address (derived
// client-side) and an Ethereum V3 keystore JSON (the private key encrypted with the user's own
// password, via web3dart's Wallet.createNew on-device); login hands that same encrypted blob
// back so the app can decrypt it locally. The account password only ever protects: (1) this
// login itself (hashed with bcrypt, standard practice) and (2) the keystore encryption, which
// the backend never has the key to reverse.
package auth

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"
)

var (
	ErrUsernameTaken      = errors.New("that username is already taken")
	ErrEmailTaken         = errors.New("that email is already registered")
	ErrInvalidCredentials = errors.New("invalid email or password")
	ErrInvalidUsername    = errors.New("username must be 3-24 characters (letters, numbers, underscore)")
	ErrInvalidEmail       = errors.New("that doesn't look like a valid email address")
	ErrPasswordTooShort   = errors.New("password must be at least 8 characters")
	ErrWalletTaken        = errors.New("that wallet address is already registered")
)

var usernamePattern = regexp.MustCompile(`^[a-zA-Z0-9_]{3,24}$`)
var emailPattern = regexp.MustCompile(`^[^@\s]+@[^@\s]+\.[^@\s]+$`)

type Service struct {
	db *pgxpool.Pool
}

func NewService(db *pgxpool.Pool) *Service {
	return &Service{db: db}
}

type Account struct {
	WalletAddress string `json:"walletAddress"`
	Username      string `json:"username"`
}

// Register creates a new account for a wallet the mobile app already generated locally.
// walletBackup is the password-encrypted Ethereum V3 keystore JSON -- opaque to the backend,
// stored only so Login can hand it back for the app to decrypt with the same password.
func (s *Service) Register(ctx context.Context, username, email, password, walletAddress, walletBackup string) (*Account, error) {
	username = strings.TrimSpace(username)
	email = strings.ToLower(strings.TrimSpace(email))
	if !usernamePattern.MatchString(username) {
		return nil, ErrInvalidUsername
	}
	if !emailPattern.MatchString(email) {
		return nil, ErrInvalidEmail
	}
	if len(password) < 8 {
		return nil, ErrPasswordTooShort
	}
	if walletAddress == "" || walletBackup == "" {
		return nil, errors.New("walletAddress and walletBackup are required")
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return nil, fmt.Errorf("hashing password: %w", err)
	}

	_, err = s.db.Exec(ctx, `
		INSERT INTO players (wallet_address, username, email, password_hash, wallet_backup)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (wallet_address) DO UPDATE
		SET username = $2, email = $3, password_hash = $4, wallet_backup = $5
		WHERE players.username IS NULL`, // never silently take over an already-registered wallet row
		walletAddress, username, email, string(hash), walletBackup)
	if err != nil {
		if pgErr := pgUniqueViolation(err); pgErr != "" {
			switch pgErr {
			case "players_username_key":
				return nil, ErrUsernameTaken
			case "players_email_key":
				return nil, ErrEmailTaken
			}
		}
		return nil, fmt.Errorf("creating account: %w", err)
	}

	var existingUsername *string
	if err := s.db.QueryRow(ctx, `SELECT username FROM players WHERE wallet_address = $1`, walletAddress).Scan(&existingUsername); err != nil {
		return nil, fmt.Errorf("confirming account: %w", err)
	}
	if existingUsername == nil || *existingUsername != username {
		return nil, ErrWalletTaken
	}

	return &Account{WalletAddress: walletAddress, Username: username}, nil
}

// Login verifies email+password and hands back the wallet address and encrypted keystore --
// the mobile app decrypts it locally with the same password to recover the signing key.
func (s *Service) Login(ctx context.Context, email, password string) (walletAddress, walletBackup, username string, err error) {
	email = strings.ToLower(strings.TrimSpace(email))
	var hash string
	err = s.db.QueryRow(ctx,
		`SELECT wallet_address, password_hash, wallet_backup, username FROM players WHERE email = $1`, email,
	).Scan(&walletAddress, &hash, &walletBackup, &username)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", "", "", ErrInvalidCredentials
		}
		return "", "", "", err
	}
	if bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) != nil {
		return "", "", "", ErrInvalidCredentials
	}
	return walletAddress, walletBackup, username, nil
}

// pgUniqueViolation returns the violated constraint name if err is a Postgres unique-violation
// (23505), else "".
func pgUniqueViolation(err error) string {
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23505" {
		return pgErr.ConstraintName
	}
	return ""
}

// lab-kms-plugin: a minimal KMS v2 plugin built with the high-level library the docs point to
// (k8s.io/kms/pkg/service). NOT for production - the "remote KMS" is a local key file.
//
//	lab-kms-plugin -listen unix:///var/run/kmsplugin/socket.sock -keys /etc/lab-kms/keys
//
// The keys file has one KEK per line: "<key_id> <base64 32-byte key>". The LAST line is the current KEK
// (used for Encrypt and reported by Status); all lines can Decrypt. The file is re-read on every call,
// so appending a line rotates the KEK without restarting anything (like rotating a key in a cloud KMS).
// The API server sends the plugin only small DEKs (envelope encryption) - never the objects themselves.
package main

import (
	"bufio"
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"k8s.io/kms/pkg/service"
)

type plugin struct{ keysFile string }

type kek struct {
	id  string
	key []byte
}

func (p *plugin) keks() ([]kek, error) {
	f, err := os.Open(p.keysFile)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	var out []kek
	s := bufio.NewScanner(f)
	for s.Scan() {
		parts := strings.Fields(s.Text())
		if len(parts) != 2 {
			continue
		}
		k, err := base64.StdEncoding.DecodeString(parts[1])
		if err != nil || len(k) != 32 {
			return nil, fmt.Errorf("key %q: need base64 of 32 bytes", parts[0])
		}
		out = append(out, kek{parts[0], k})
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("no keys in %s", p.keysFile)
	}
	return out, nil
}

func gcm(key []byte) (cipher.AEAD, error) {
	b, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	return cipher.NewGCM(b)
}

// Status: polled by the API server ~every minute; key_id here is authoritative.
func (p *plugin) Status(ctx context.Context) (*service.StatusResponse, error) {
	ks, err := p.keks()
	if err != nil {
		return &service.StatusResponse{Version: "v2", Healthz: err.Error()}, nil
	}
	return &service.StatusResponse{Version: "v2", Healthz: "ok", KeyID: ks[len(ks)-1].id}, nil
}

// Encrypt: wraps a DEK with the current KEK. Response key_id MUST equal Status' key_id.
func (p *plugin) Encrypt(ctx context.Context, uid string, data []byte) (*service.EncryptResponse, error) {
	ks, err := p.keks()
	if err != nil {
		return nil, err
	}
	cur := ks[len(ks)-1]
	a, err := gcm(cur.key)
	if err != nil {
		return nil, err
	}
	nonce := make([]byte, a.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return nil, err
	}
	log.Printf("Encrypt uid=%s with key_id=%s (%d bytes)", uid, cur.id, len(data))
	return &service.EncryptResponse{
		Ciphertext: a.Seal(nonce, nonce, data, nil),
		KeyID:      cur.id,
		// annotation keys must be DNS subdomains WITHOUT "/" (the API server rejects "lab-kms.example.com/kek")
		Annotations: map[string][]byte{"kek.lab-kms.example.com": []byte(cur.id)},
	}, nil
}

// Decrypt: must refuse key_ids it doesn't know.
func (p *plugin) Decrypt(ctx context.Context, uid string, req *service.DecryptRequest) ([]byte, error) {
	ks, err := p.keks()
	if err != nil {
		return nil, err
	}
	for _, k := range ks {
		if k.id != req.KeyID {
			continue
		}
		a, err := gcm(k.key)
		if err != nil {
			return nil, err
		}
		ns := a.NonceSize()
		if len(req.Ciphertext) < ns {
			return nil, fmt.Errorf("ciphertext too short")
		}
		log.Printf("Decrypt uid=%s with key_id=%s", uid, k.id)
		return a.Open(nil, req.Ciphertext[:ns], req.Ciphertext[ns:], nil)
	}
	return nil, fmt.Errorf("unknown key_id %q", req.KeyID)
}

func main() {
	listen := flag.String("listen", "unix:///var/run/kmsplugin/socket.sock", "gRPC listen address (unix socket)")
	keys := flag.String("keys", "/etc/lab-kms/keys", "KEK file: '<key_id> <base64 key>' per line, last = current")
	flag.Parse()
	p := &plugin{keysFile: *keys}
	if _, err := p.keks(); err != nil {
		log.Fatal(err)
	}
	addr := strings.TrimPrefix(*listen, "unix://")
	_ = os.Remove(addr)
	svc := service.NewGRPCService(addr, 3*time.Second, p)
	go func() {
		ch := make(chan os.Signal, 1)
		signal.Notify(ch, syscall.SIGINT, syscall.SIGTERM)
		<-ch
		svc.Shutdown()
	}()
	log.Printf("lab KMS v2 plugin listening on %s, keys from %s", addr, *keys)
	if err := svc.ListenAndServe(); err != nil {
		log.Fatal(err)
	}
}

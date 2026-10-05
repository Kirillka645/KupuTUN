//go:build !nosingbox

package bridge

import (
	"context"

	box "github.com/sagernet/sing-box"
	C "github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/common/json"
)

type singboxEngine struct {
	b      *box.Box
	cancel context.CancelFunc
}

func (e *singboxEngine) Start() error { return e.b.Start() }
// Traffic: sing-box has no in-process counter API without clash_api;
// the bridge falls back to tun2socks / platform counters.
func (e *singboxEngine) Traffic() (int64, int64) { return 0, 0 }

func (e *singboxEngine) Close() error {
	err := e.b.Close()
	e.cancel()
	return err
}

func init() {
	registerFactory("singbox", func(cfg string) (coreEngine, error) {
		ctx, cancel := context.WithCancel(include.Context(context.Background()))
		opts, err := json.UnmarshalExtendedContext[option.Options](ctx, []byte(cfg))
		if err != nil {
			cancel()
			return nil, err
		}
		b, err := box.New(box.Options{Context: ctx, Options: opts})
		if err != nil {
			cancel()
			return nil, err
		}
		return &singboxEngine{b: b, cancel: cancel}, nil
	})
	versionProviders["singbox"] = func() string { return C.Version }
}

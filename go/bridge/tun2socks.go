package bridge

import (
	"fmt"
	"sync"
	"time"

	"github.com/xjasonlyu/tun2socks/v2/engine"
	"github.com/xjasonlyu/tun2socks/v2/tunnel/statistic"
)

func tunTraffic() (int64, int64) {
	snap := statistic.DefaultManager.Snapshot()
	return snap.UploadTotal, snap.DownloadTotal
}

var tunMu sync.Mutex
var tunRunning bool

// StartTun2Socks bridges a TUN device to a local SOCKS5 inbound of the core.
// device: "fd://<n>" on Android (fd from VpnService), "tun://kuputun0" on
// Linux/macOS, "wintun" on Windows. Decision: tun2socks is the universal TUN
// path because it needs only a SOCKS inbound, so it works with both cores.
func StartTun2Socks(device string, socksPort int, mtu int, logLevel string) (err error) {
	tunMu.Lock()
	defer tunMu.Unlock()
	if tunRunning {
		tunRunning = false
		func() {
			defer func() { _ = recover() }()
			engine.Stop()
		}()
	}
	if mtu <= 0 {
		mtu = 1500
	}
	if logLevel == "" {
		logLevel = "warn"
	}
	defer func() {
		if r := recover(); r != nil {
			err = fmt.Errorf("tun2socks: %v", r)
		}
	}()
	engine.Insert(&engine.Key{
		Device:     device,
		Proxy:      fmt.Sprintf("socks5://127.0.0.1:%d", socksPort),
		MTU:        mtu,
		LogLevel:   logLevel,
		UDPTimeout: 60 * time.Second,
	})
	engine.Start()
	tunRunning = true
	return nil
}

// StopTun2Socks stops the TUN bridge.
func StopTun2Socks() {
	tunMu.Lock()
	defer tunMu.Unlock()
	if !tunRunning {
		return
	}
	tunRunning = false
	// A panic here would kill the whole app process (gomobile), e.g. when
	// the TUN fd is already gone after onRevoke — never let it escape.
	defer func() { _ = recover() }()
	engine.Stop()
}

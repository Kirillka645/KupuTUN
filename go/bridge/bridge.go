// Package bridge is the single native entry point used by the Flutter app.
// It is compiled two ways:
//   - gomobile bind  -> Android .aar / iOS .xcframework (exported funcs below)
//   - c-shared       -> .so/.dll/.dylib for desktop via cmd/libkuputun (Dart FFI)
//
// Decision: the bridge only knows how to run cores by *JSON config*. All config
// generation (links -> outbounds, routing, DNS, fragmentation) lives in Dart, so
// it is unit-testable and identical on every platform.
package bridge

import (
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"sync"
)

// coreEngine is implemented by the Xray and sing-box adapters.
type coreEngine interface {
	Start() error
	Close() error
	// Traffic returns cumulative proxied bytes (uplink, downlink).
	Traffic() (int64, int64)
}

type engineFactory func(configJSON string) (coreEngine, error)

var (
	factories   = map[string]engineFactory{}
	factoriesMu sync.RWMutex

	instances   = map[string]coreEngine{}
	instancesMu sync.Mutex
)

func registerFactory(name string, f engineFactory) {
	factoriesMu.Lock()
	defer factoriesMu.Unlock()
	factories[name] = f
}

// AvailableCores returns a JSON array of compiled-in cores, e.g. ["xray","singbox"].
func AvailableCores() string {
	factoriesMu.RLock()
	defer factoriesMu.RUnlock()
	names := make([]string, 0, len(factories))
	for k := range factories {
		names = append(names, k)
	}
	b, _ := json.Marshal(names)
	return string(b)
}

// StartInstance launches a core with the given JSON config under an id.
// id "main" is the user connection; "test-*" ids are throw-away tester instances.
// Starting an id that already runs replaces it (stop-then-start).
func StartInstance(id, core, configJSON string) error {
	factoriesMu.RLock()
	f, ok := factories[core]
	factoriesMu.RUnlock()
	if !ok {
		return fmt.Errorf("core %q is not compiled into this build", core)
	}
	_ = StopInstance(id)
	eng, err := f(configJSON)
	if err != nil {
		return fmt.Errorf("config error: %w", err)
	}
	if err := eng.Start(); err != nil {
		_ = eng.Close()
		return fmt.Errorf("start error: %w", err)
	}
	instancesMu.Lock()
	instances[id] = eng
	instancesMu.Unlock()
	return nil
}

// StopInstance stops an instance; stopping a missing id is not an error.
func StopInstance(id string) error {
	instancesMu.Lock()
	eng, ok := instances[id]
	delete(instances, id)
	instancesMu.Unlock()
	if !ok {
		return nil
	}
	return safeClose(eng)
}

// safeClose stops a core without letting a panic inside Xray/sing-box
// shutdown crash the app (Go panics are fatal for the whole process).
func safeClose(eng interface{ Close() error }) (err error) {
	defer func() {
		if r := recover(); r != nil {
			err = fmt.Errorf("stop: %v", r)
		}
	}()
	return eng.Close()
}

// StopAll stops every running instance (used on app exit / kill switch reset).
func StopAll() {
	instancesMu.Lock()
	ids := make([]string, 0, len(instances))
	for id := range instances {
		ids = append(ids, id)
	}
	instancesMu.Unlock()
	for _, id := range ids {
		_ = StopInstance(id)
	}
}

// IsRunning reports whether an instance id is active.
func IsRunning(id string) bool {
	instancesMu.Lock()
	defer instancesMu.Unlock()
	_, ok := instances[id]
	return ok
}

// FreePorts reserves n free TCP ports on 127.0.0.1 and returns them as a JSON
// array. Ports are released right before returning, so callers should start
// the instance immediately (race window is a few ms, acceptable for a tester).
func FreePorts(n int) (string, error) {
	if n <= 0 || n > 4096 {
		return "", errors.New("n must be in 1..4096")
	}
	listeners := make([]net.Listener, 0, n)
	ports := make([]int, 0, n)
	defer func() {
		for _, l := range listeners {
			_ = l.Close()
		}
	}()
	for i := 0; i < n; i++ {
		l, err := net.Listen("tcp", "127.0.0.1:0")
		if err != nil {
			return "", err
		}
		listeners = append(listeners, l)
		ports = append(ports, l.Addr().(*net.TCPAddr).Port)
	}
	b, _ := json.Marshal(ports)
	return string(b), nil
}

// Version returns bridge + core versions as JSON.
func Version() string {
	v := map[string]string{"bridge": "1.0.0"}
	for k, fn := range versionProviders {
		v[k] = fn()
	}
	b, _ := json.Marshal(v)
	return string(b)
}

var versionProviders = map[string]func() string{}

// SetAssetDir points Xray to geoip.dat / geosite.dat (downloaded by the app)
// and sing-box to its rule-set cache directory. Must be called before
// StartInstance.
func SetAssetDir(dir string) error {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	if err := os.Setenv("xray.location.asset", dir); err != nil {
		return err
	}
	return os.Setenv("XRAY_LOCATION_ASSET", dir)
}

// TrafficStats returns {"up":N,"down":N} cumulative bytes for an instance.
// When the core cannot report (sing-box), tun2socks counters are used.
func TrafficStats(id string) string {
	instancesMu.Lock()
	eng, ok := instances[id]
	instancesMu.Unlock()
	var up, down int64
	if ok {
		up, down = eng.Traffic()
	}
	if up == 0 && down == 0 {
		up, down = tunTraffic()
	}
	b, _ := json.Marshal(map[string]int64{"up": up, "down": down})
	return string(b)
}

// c-shared wrapper for desktop. Build:
//   go build -buildmode=c-shared -trimpath -ldflags="-s -w -buildid=" \
//     -tags "with_quic,with_utls,with_wireguard,with_gvisor" \
//     -o libkuputun.so ./cmd/libkuputun
// Every function returns a malloc'ed C string: "" on success or an error text
// (or a JSON payload for getters). Dart must call KtFree on it.
package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"unsafe"

	"github.com/kuputun/kuputun/go/bridge"
)

func cstr(s string) *C.char { return C.CString(s) }

func errStr(err error) *C.char {
	if err == nil {
		return cstr("")
	}
	return cstr(err.Error())
}

//export KtStartInstance
func KtStartInstance(id, core, cfg *C.char) *C.char {
	return errStr(bridge.StartInstance(C.GoString(id), C.GoString(core), C.GoString(cfg)))
}

//export KtStopInstance
func KtStopInstance(id *C.char) *C.char { return errStr(bridge.StopInstance(C.GoString(id))) }

//export KtStopAll
func KtStopAll() { bridge.StopAll() }

//export KtIsRunning
func KtIsRunning(id *C.char) C.int {
	if bridge.IsRunning(C.GoString(id)) {
		return 1
	}
	return 0
}

//export KtSetAssetDir
func KtSetAssetDir(dir *C.char) *C.char { return errStr(bridge.SetAssetDir(C.GoString(dir))) }

//export KtTrafficStats
func KtTrafficStats(id *C.char) *C.char { return cstr(bridge.TrafficStats(C.GoString(id))) }

//export KtFreePorts
func KtFreePorts(n C.int) *C.char {
	s, err := bridge.FreePorts(int(n))
	if err != nil {
		return cstr("ERR:" + err.Error())
	}
	return cstr(s)
}

//export KtStartTun2Socks
func KtStartTun2Socks(device *C.char, socksPort, mtu C.int, level *C.char) *C.char {
	return errStr(bridge.StartTun2Socks(C.GoString(device), int(socksPort), int(mtu), C.GoString(level)))
}

//export KtStopTun2Socks
func KtStopTun2Socks() { bridge.StopTun2Socks() }

//export KtAvailableCores
func KtAvailableCores() *C.char { return cstr(bridge.AvailableCores()) }

//export KtVersion
func KtVersion() *C.char { return cstr(bridge.Version()) }

//export KtFree
func KtFree(p *C.char) { C.free(unsafe.Pointer(p)) }

func main() {}

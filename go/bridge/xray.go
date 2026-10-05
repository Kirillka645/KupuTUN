//go:build !noxray

package bridge

import (
	"bytes"
	"strings"

	"github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/features/stats"
	_ "github.com/xtls/xray-core/main/distro/all" // registers all Xray features
	"github.com/xtls/xray-core/infra/conf/serial"
)

type xrayEngine struct{ inst *core.Instance }

func (e *xrayEngine) Start() error { return e.inst.Start() }
func (e *xrayEngine) Close() error { return e.inst.Close() }

// Traffic sums outbound counters of every proxy-* outbound (main or balanced).
func (e *xrayEngine) Traffic() (int64, int64) {
	m, ok := e.inst.GetFeature(stats.ManagerType()).(interface {
		VisitCounters(func(string, stats.Counter) bool)
	})
	if !ok {
		return 0, 0
	}
	var up, down int64
	m.VisitCounters(func(name string, c stats.Counter) bool {
		// name: outbound>>>proxy-3>>>traffic>>>uplink
		parts := strings.Split(name, ">>>")
		if len(parts) == 4 && parts[0] == "outbound" && strings.HasPrefix(parts[1], "proxy") {
			if parts[3] == "uplink" {
				up += c.Value()
			} else if parts[3] == "downlink" {
				down += c.Value()
			}
		}
		return true
	})
	return up, down
}

func init() {
	registerFactory("xray", func(cfg string) (coreEngine, error) {
		jsonCfg, err := serial.DecodeJSONConfig(bytes.NewReader([]byte(cfg)))
		if err != nil {
			return nil, err
		}
		pb, err := jsonCfg.Build()
		if err != nil {
			return nil, err
		}
		inst, err := core.New(pb)
		if err != nil {
			return nil, err
		}
		return &xrayEngine{inst: inst}, nil
	})
	versionProviders["xray"] = core.Version
}

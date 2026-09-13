# Guarded plugin machine actions

Exercise the guarded brewing scale machine state contract in simulate mode.
This uses the existing `MockDe1` and `MockScale`; the source selection token
is returned by the current scale connection projection.

## Preconditions

```bash
scripts/sb-dev.sh start --connect-machine MockDe1 --connect-scale MockScale
BASE=http://localhost:8080
```

## Steps

Read the machine identity and generation exposed for plugin guards:

```bash
curl -sf "$BASE/api/v1/machine/state" |
  jq -e '.deviceId == "MockDe1" and (.connectionGeneration | type == "number")'
```

Capture the current generation and start from idle:

```bash
GEN=$(curl -sf "$BASE/api/v1/machine/state" | jq -r '.connectionGeneration')
BREWING=$(curl -sf "$BASE/api/v1/scale/connections" | jq -c '.brewing')
curl -sf -X PUT "$BASE/api/v1/machine/state/espresso" \
  -H 'content-type: application/json' \
  --data "$(jq -nc --argjson scale "$BREWING" --arg machine MockDe1 --argjson generation "$GEN" '{guarded:true,expectedMachineId:$machine,expectedMachineGeneration:$generation,expectedState:"idle",requireInactiveGhc:true,sourceScale:{role:"brewing",deviceId:$scale.deviceId,connectionId:$scale.connectionId,selectionId:$scale.selectionId}}')" |
  jq -e ' . == null '
```

Stop through the immediate guarded path after the machine reports espresso:

```bash
GEN=$(curl -sf "$BASE/api/v1/machine/state" | jq -r '.connectionGeneration')
BREWING=$(curl -sf "$BASE/api/v1/scale/connections" | jq -c '.brewing')
curl -sf -X PUT "$BASE/api/v1/machine/state/idle" \
  -H 'content-type: application/json' \
  --data "$(jq -nc --argjson scale "$BREWING" --arg machine MockDe1 --argjson generation "$GEN" '{guarded:true,expectedMachineId:$machine,expectedMachineGeneration:$generation,expectedState:"espresso",requireInactiveGhc:false,sourceScale:{role:"brewing",deviceId:$scale.deviceId,connectionId:$scale.connectionId,selectionId:$scale.selectionId}}')" |
  jq -e ' . == null '
```

Verify dosing sources are rejected without a machine write:

```bash
GEN=$(curl -sf "$BASE/api/v1/machine/state" | jq -r '.connectionGeneration')
BREWING=$(curl -sf "$BASE/api/v1/scale/connections" | jq -c '.brewing')
curl -sS -o /tmp/guarded-dosing.json -w '%{http_code}\n' \
  -X PUT "$BASE/api/v1/machine/state/espresso" \
  -H 'content-type: application/json' \
  --data "$(jq -nc --argjson scale "$BREWING" --arg machine MockDe1 --argjson generation "$GEN" '{guarded:true,expectedMachineId:$machine,expectedMachineGeneration:$generation,expectedState:"idle",requireInactiveGhc:true,sourceScale:{role:"dosing",deviceId:$scale.deviceId,connectionId:$scale.connectionId,selectionId:$scale.selectionId}}')" | grep -qx 409
jq -e '.type == "guarded_action_rejected"' /tmp/guarded-dosing.json
```

## Postconditions

```bash
curl -sf "$BASE/api/v1/machine/state" | jq -e '.state.state == "idle"'
scripts/sb-dev.sh stop
```

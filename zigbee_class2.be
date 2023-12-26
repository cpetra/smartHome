class dmconfig
    var dmid
    var zbid
    var stype
    var endpoint
    var last_value
    def init(arr)
        self.dmid = number(arr[0])
        self.zbid = number(arr[1])
        self.stype = arr[2]
        if (arr.size() > 3)
            self.endpoint = arr[3]
        end
        self.last_value = -1
    end
end

class mqttDomoticz
    var config

    def init()
        import mqtt
        mqtt.subscribe("domoticz/out")
        self.parse_config("/domoticz_config.txt")
        print("mqttDomoticz driver initialized")
    end
    def parse_config(filename)
        var file = open(filename, 'r')
        self.config = []
        if file != nil
            import re
            import string
            while true
                var line = file.readline()
                if line == nil || line == ""
                    break
                end 
                line = string.replace(line, "\n", "")
                var parts = re.split(', ', line)
                self.config.push(dmconfig(parts))
                print(parts)
            end
        end
    end
    def domoticz_publish(id, value)
        if self.config[id].last_value == value
            return
        end

        import string
        var domoticz_id = self.config[id].dmid
        var cmd = string.format("publish domoticz/in {\"idx\":%d,\"svalue\": \"%.1f\"}", domoticz_id, value)
        tasmota.cmd(cmd)
        self.config[id].last_value = value
    end
    def zigbee_send_setpoint(id, setpoint)
        if self.config[id].last_value == setpoint
            print("zigbee same")
            return
        end
        import string
        var val = setpoint * 10
        var zigbee_id = self.config[id].zbid
        var endpoint = self.config[id].endpoint
        var msg = string.format("zbSend {\"Device\": \"0x%x\", \"Write\": {\"%s\": %d }}",
            zigbee_id, endpoint, val)
        print(msg)
        tasmota.cmd(msg)
        self.config[id].last_value = setpoint
    end

    def hasDmConfig(sz, xtype)
        var v = 0
        for n: self.config
            if n.dmid == number(sz) && n.stype == xtype
                return v
            end
            v = v + 1
        end
        return nil
    end

    def hasZbConfig(sz, xtype)
        var v = 0
        for n: self.config
            if n.zbid == number(sz) && n.stype == xtype
                return v
            end
            v = v + 1
        end
        return nil
    end

    def mqtt_data(topic, nidx, payload_s, payload_b)
        import json
        import string
        if topic == "domoticz/out"
            var payload = json.load(payload_s)
            # Only handle domoticz command if this is heating setpoint
            var id = self.hasDmConfig(payload['idx'], 'OccupiedHeatingSetpoint')
            if id != nil
                var value = number(payload['svalue1'])
                self.zigbee_send_setpoint(id, value)
                return true
            end
            return true
        end
        # return false, let other components handle this message
        return false
    end
    # handle zigbee object
    def handle_zb_object(key, value, idx)
        print(f"handling zb data {key} {value} {idx}")
        var id = self.hasZbConfig(idx, key)
        if id != nil
            self.domoticz_publish(id, number(value))
        end
    end
    # handle zigbee refined messages only
    def attributes_refined(event_type, frame, attr_list, idx)
        print(frame)
        print(attr_list)
        if attr_list != nil
            for n:0..(attr_list.size() - 1)
                self.handle_zb_object(attr_list[n].key, attr_list[n].val, idx)
            end
        end
    end
    def unsubscribe()
        import mqtt
        mqtt.unsubscribe("domoticz/out")
    end
end

import zigbee

d1 = mqttDomoticz()
tasmota.add_driver(d1)
zigbee.add_handler(d1)

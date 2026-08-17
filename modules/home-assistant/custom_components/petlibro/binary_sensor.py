"""Binary sensor platform for PetLibro Feeders."""

import time
from homeassistant.components.binary_sensor import (
    BinarySensorDeviceClass,
    BinarySensorEntity,
)
from homeassistant.core import callback
from .const import DOMAIN


async def async_setup_entry(hass, entry, async_add_entities):
    """Set up binary sensors for PetLibro entry."""
    coordinator = hass.data[DOMAIN][entry.entry_id]
    entities = []

    for feeder in coordinator.feeders:
        name = feeder["name"]
        device_id = feeder["device_id"]
        entities.append(PetLibroOnlineBinarySensor(coordinator, name, device_id))
        entities.append(PetLibroFeedJamBinarySensor(coordinator, name, device_id))

    async_add_entities(entities)


class PetLibroBaseBinarySensor(BinarySensorEntity):
    """Base class for PetLibro binary sensors."""

    def __init__(self, coordinator, feeder_name: str, device_id: str):
        self.coordinator = coordinator
        self.feeder_name = feeder_name
        self.device_id = device_id
        self._attr_device_info = {
            "identifiers": {(DOMAIN, f"plaf301_{device_id}")},
            "name": feeder_name,
            "manufacturer": "PETLIBRO",
            "model": "PLAF301",
        }

    async def async_added_to_hass(self):
        self.coordinator.add_listener(self._handle_coordinator_update)

    async def async_will_remove_from_hass(self):
        self.coordinator.remove_listener(self._handle_coordinator_update)

    @callback
    def _handle_coordinator_update(self):
        self.async_write_ha_state()


class PetLibroOnlineBinarySensor(PetLibroBaseBinarySensor):
    """Connectivity binary sensor based on MQTT heartbeat."""

    _attr_device_class = BinarySensorDeviceClass.CONNECTIVITY

    def __init__(self, coordinator, feeder_name: str, device_id: str):
        super().__init__(coordinator, feeder_name, device_id)
        self._attr_name = f"{feeder_name} Online"
        self._attr_unique_id = f"{device_id}_online"

    @property
    def is_on(self) -> bool:
        state = self.coordinator.feeder_states.get(self.feeder_name, {})
        last_hb = state.get("last_heartbeat", 0)
        # Online if a heartbeat was received within the last 150 seconds
        return (time.time() - last_hb) < 150


class PetLibroFeedJamBinarySensor(PetLibroBaseBinarySensor):
    """Problem binary sensor for grain jam detection."""

    _attr_device_class = BinarySensorDeviceClass.PROBLEM

    def __init__(self, coordinator, feeder_name: str, device_id: str):
        super().__init__(coordinator, feeder_name, device_id)
        self._attr_name = f"{feeder_name} Feed Jam"
        self._attr_unique_id = f"{device_id}_feed_jam"

    @property
    def is_on(self) -> bool:
        state = self.coordinator.feeder_states.get(self.feeder_name, {})
        return state.get("feed_jam", False)

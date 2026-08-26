"""Sensor platform for PetLibro Feeders."""

from homeassistant.components.sensor import (
    SensorDeviceClass,
    SensorEntity,
    SensorStateClass,
)
from homeassistant.core import callback
from homeassistant.helpers.entity import EntityCategory
from .const import DOMAIN


async def async_setup_entry(hass, entry, async_add_entities):
    """Set up sensors for PetLibro entry."""
    coordinator = hass.data[DOMAIN][entry.entry_id]
    entities = []

    for feeder in coordinator.feeders:
        name = feeder["name"]
        device_id = feeder["device_id"]
        entities.extend([
            PetLibroRSSISensor(coordinator, name, device_id),
            PetLibroLastFedSensor(coordinator, name, device_id),
            PetLibroPetScannedSensor(coordinator, name, device_id),
            PetLibroLastActivitySensor(coordinator, name, device_id),
            PetLibroBowlActivitySensor(coordinator, name, device_id),
            PetLibroLastErrorSensor(coordinator, name, device_id),
            PetLibroLastBootSensor(coordinator, name, device_id),
            PetLibroLastServiceResponseSensor(coordinator, name, device_id),
        ])

    async_add_entities(entities)


class PetLibroBaseSensor(SensorEntity):
    """Base class for PetLibro sensors."""

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


class PetLibroRSSISensor(PetLibroBaseSensor):
    """Signal strength sensor."""

    _attr_device_class = SensorDeviceClass.SIGNAL_STRENGTH
    _attr_state_class = SensorStateClass.MEASUREMENT
    _attr_native_unit_of_measurement = "dBm"
    _attr_entity_category = EntityCategory.DIAGNOSTIC

    def __init__(self, coordinator, feeder_name: str, device_id: str):
        super().__init__(coordinator, feeder_name, device_id)
        self._attr_name = f"{feeder_name} Signal Strength"
        self._attr_unique_id = f"{device_id}_rssi"

    @property
    def native_value(self):
        state = self.coordinator.feeder_states.get(self.feeder_name, {})
        return state.get("rssi")


class PetLibroLastFedSensor(PetLibroBaseSensor):
    """Timestamp sensor of last completed feeding."""

    _attr_device_class = SensorDeviceClass.TIMESTAMP
    _attr_icon = "mdi:food-drumstick"

    def __init__(self, coordinator, feeder_name: str, device_id: str):
        super().__init__(coordinator, feeder_name, device_id)
        self._attr_name = f"{feeder_name} Last Fed"
        self._attr_unique_id = f"{device_id}_last_fed"

    @property
    def native_value(self):
        state = self.coordinator.feeder_states.get(self.feeder_name, {})
        return state.get("last_fed")


class PetLibroPetScannedSensor(PetLibroBaseSensor):
    """Sensor tracking the last pet / collar tag scanned by feeder RFID."""

    _attr_icon = "mdi:paw"

    def __init__(self, coordinator, feeder_name: str, device_id: str):
        super().__init__(coordinator, feeder_name, device_id)
        self._attr_name = f"{feeder_name} Pet Last Scanned"
        self._attr_unique_id = f"{device_id}_last_scanned"

    @property
    def native_value(self):
        state = self.coordinator.feeder_states.get(self.feeder_name, {})
        return state.get("last_scanned_pet") or "None"

    @property
    def extra_state_attributes(self):
        state = self.coordinator.feeder_states.get(self.feeder_name, {})
        tag = state.get("last_scanned_tag")
        pet_name = state.get("last_scanned_pet")
        return {
            "collar_tag": tag,
            "pet_name": pet_name,
        }


class PetLibroLastActivitySensor(PetLibroBaseSensor):
    """Timestamp sensor of last RFID collar read."""

    _attr_device_class = SensorDeviceClass.TIMESTAMP
    _attr_icon = "mdi:rfid"

    def __init__(self, coordinator, feeder_name: str, device_id: str):
        super().__init__(coordinator, feeder_name, device_id)
        self._attr_name = f"{feeder_name} Last Activity"
        self._attr_unique_id = f"{device_id}_last_activity"

    @property
    def native_value(self):
        state = self.coordinator.feeder_states.get(self.feeder_name, {})
        return state.get("last_activity")


class PetLibroBowlActivitySensor(PetLibroBaseSensor):
    """Timestamp sensor of bowl break-beam activity."""

    _attr_device_class = SensorDeviceClass.TIMESTAMP
    _attr_icon = "mdi:bowl"

    def __init__(self, coordinator, feeder_name: str, device_id: str):
        super().__init__(coordinator, feeder_name, device_id)
        self._attr_name = f"{feeder_name} Bowl Activity"
        self._attr_unique_id = f"{device_id}_bowl_activity"

    @property
    def native_value(self):
        state = self.coordinator.feeder_states.get(self.feeder_name, {})
        return state.get("bowl_activity")


class PetLibroLastErrorSensor(PetLibroBaseSensor):
    """Last error reported by feeder."""

    _attr_icon = "mdi:alert"

    def __init__(self, coordinator, feeder_name: str, device_id: str):
        super().__init__(coordinator, feeder_name, device_id)
        self._attr_name = f"{feeder_name} Last Error"
        self._attr_unique_id = f"{device_id}_last_error"

    @property
    def native_value(self):
        state = self.coordinator.feeder_states.get(self.feeder_name, {})
        return state.get("last_error") or "None"


class PetLibroLastBootSensor(PetLibroBaseSensor):
    """Timestamp sensor of last reboot."""

    _attr_device_class = SensorDeviceClass.TIMESTAMP
    _attr_entity_category = EntityCategory.DIAGNOSTIC

    def __init__(self, coordinator, feeder_name: str, device_id: str):
        super().__init__(coordinator, feeder_name, device_id)
        self._attr_name = f"{feeder_name} Last Boot"
        self._attr_unique_id = f"{device_id}_last_boot"

    @property
    def native_value(self):
        state = self.coordinator.feeder_states.get(self.feeder_name, {})
        return state.get("last_boot")


class PetLibroLastServiceResponseSensor(PetLibroBaseSensor):
    """Last service command response code."""

    _attr_icon = "mdi:message-reply-text"
    _attr_entity_category = EntityCategory.DIAGNOSTIC

    def __init__(self, coordinator, feeder_name: str, device_id: str):
        super().__init__(coordinator, feeder_name, device_id)
        self._attr_name = f"{feeder_name} Last Service Response"
        self._attr_unique_id = f"{device_id}_last_service_response"

    @property
    def native_value(self):
        state = self.coordinator.feeder_states.get(self.feeder_name, {})
        resp = state.get("last_service_response")
        return str(resp) if resp is not None else "None"

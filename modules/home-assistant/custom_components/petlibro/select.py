"""Select platform for PetLibro Feeders."""

from homeassistant.components.select import SelectEntity
from homeassistant.core import callback
from .const import CMD_ATTR_SET, CMD_DISPLAY_MATRIX, DOMAIN


async def async_setup_entry(hass, entry, async_add_entities):
    """Set up select entities for PetLibro entry."""
    coordinator = hass.data[DOMAIN][entry.entry_id]
    entities = []

    for feeder in coordinator.feeders:
        name = feeder["name"]
        device_id = feeder["device_id"]
        entities.extend([
            PetLibroDisplaySceneSelect(coordinator, name, device_id),
            PetLibroCloseSpeedSelect(coordinator, name, device_id),
        ])

    async_add_entities(entities)


class PetLibroBaseSelect(SelectEntity):
    """Base select entity."""

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


class PetLibroDisplaySceneSelect(PetLibroBaseSelect):
    """Display matrix scene select entity."""

    _attr_options = ["PET_NAME", "PRODUCT_TEST", "DEFAULT_HELLO"]
    _attr_icon = "mdi:image-text"

    def __init__(self, coordinator, feeder_name: str, device_id: str):
        super().__init__(coordinator, feeder_name, device_id)
        self._attr_name = f"{feeder_name} Display Scene"
        self._attr_unique_id = f"{device_id}_display_scene"
        self._current_option = "PET_NAME"

    @property
    def current_option(self) -> str:
        return self._current_option

    async def async_select_option(self, option: str):
        self._current_option = option
        payload = {"cmd": CMD_DISPLAY_MATRIX, "displayScene": option}
        await self.coordinator.async_publish_cmd(self.feeder_name, payload)
        self.async_write_ha_state()


class PetLibroCloseSpeedSelect(PetLibroBaseSelect):
    """Lid auto-close speed select entity."""

    _attr_options = ["SLOW", "MEDIUM", "FAST"]
    _attr_icon = "mdi:speedometer"

    def __init__(self, coordinator, feeder_name: str, device_id: str):
        super().__init__(coordinator, feeder_name, device_id)
        self._attr_name = f"{feeder_name} Close Speed"
        self._attr_unique_id = f"{device_id}_close_speed"
        self._current_option = "FAST"

    @property
    def current_option(self) -> str:
        return self._current_option

    async def async_select_option(self, option: str):
        self._current_option = option
        payload = {"cmd": CMD_ATTR_SET, "coverCloseSpeed": option}
        await self.coordinator.async_publish_cmd(self.feeder_name, payload)
        self.async_write_ha_state()

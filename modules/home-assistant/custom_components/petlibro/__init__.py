"""The PetLibro Feeder integration."""

import logging
import voluptuous as vol

from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant, ServiceCall
from homeassistant.helpers import config_validation as cv

from .const import (
    DEFAULT_FEEDERS,
    DOMAIN,
    SERVICE_ASSIGN_COLLAR,
    SERVICE_FEED,
    SERVICE_SET_SCHEDULE,
    SERVICE_SET_SCHEDULE_ENABLED,
    SERVICE_SYNC_SCHEDULES,
)
from .coordinator import PetLibroCoordinator

_LOGGER = logging.getLogger(__name__)

PLATFORMS = [
    "binary_sensor",
    "sensor",
    "cover",
    "switch",
    "number",
    "select",
    "button",
    "time",
    "text",
]


async def async_setup(hass: HomeAssistant, config: dict):
    """Set up PetLibro integration from YAML if present."""
    return True


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry):
    """Set up PetLibro Feeder from a config entry."""
    feeders = entry.data.get("feeders", DEFAULT_FEEDERS)

    coordinator = PetLibroCoordinator(hass, feeders)
    await coordinator.async_setup()

    hass.data.setdefault(DOMAIN, {})
    hass.data[DOMAIN][entry.entry_id] = coordinator

    # Register custom HA services
    async def handle_feed(call: ServiceCall):
        feeder_id = call.data["feeder"]
        portions = call.data.get("portions", 1)
        await coordinator.async_manual_feed(feeder_id, portions)

    async def handle_assign_collar(call: ServiceCall):
        feeder_id = call.data["feeder"]
        pet_name = call.data["pet_name"]
        collar_tag = call.data["collar_tag"]
        await coordinator.async_assign_collar(feeder_id, pet_name, collar_tag)

    async def handle_set_schedule(call: ServiceCall):
        feeder_id = call.data["feeder"]
        time_str = call.data.get("time")
        portions = call.data.get("portions")
        repeat_day = call.data.get("repeat_day")
        enabled = call.data.get("enabled")
        linked = call.data.get("linked")
        await coordinator.async_update_schedule(
            feeder_id,
            time_str=time_str,
            grain_num=portions,
            repeat_day=repeat_day,
            enabled=enabled,
            linked=linked,
        )

    async def handle_sync_schedules(call: ServiceCall):
        source_feeder = call.data["source_feeder"]
        sched = coordinator.schedules.get(source_feeder)
        if sched:
            await coordinator.async_update_schedule(
                source_feeder,
                time_str=sched.get("time"),
                grain_num=sched.get("grain_num"),
                repeat_day=sched.get("repeat_day"),
                linked=True,
            )

    async def handle_set_schedule_enabled(call: ServiceCall):
        feeder_id = call.data["feeder"]
        enabled = call.data["enabled"]
        await coordinator.async_toggle_schedule_enabled(feeder_id, enabled)

    hass.services.async_register(
        DOMAIN,
        SERVICE_FEED,
        handle_feed,
        schema=vol.Schema({
            vol.Required("feeder"): cv.string,
            vol.Optional("portions", default=1): cv.positive_int,
        }),
    )

    hass.services.async_register(
        DOMAIN,
        SERVICE_ASSIGN_COLLAR,
        handle_assign_collar,
        schema=vol.Schema({
            vol.Required("feeder"): cv.string,
            vol.Required("pet_name"): cv.string,
            vol.Required("collar_tag"): cv.string,
        }),
    )

    hass.services.async_register(
        DOMAIN,
        SERVICE_SET_SCHEDULE,
        handle_set_schedule,
        schema=vol.Schema({
            vol.Required("feeder"): cv.string,
            vol.Optional("time"): cv.string,
            vol.Optional("portions"): cv.positive_int,
            vol.Optional("repeat_day"): cv.string,
            vol.Optional("enabled"): cv.boolean,
            vol.Optional("linked"): cv.boolean,
        }),
    )

    hass.services.async_register(
        DOMAIN,
        SERVICE_SYNC_SCHEDULES,
        handle_sync_schedules,
        schema=vol.Schema({
            vol.Required("source_feeder"): cv.string,
        }),
    )

    hass.services.async_register(
        DOMAIN,
        SERVICE_SET_SCHEDULE_ENABLED,
        handle_set_schedule_enabled,
        schema=vol.Schema({
            vol.Required("feeder"): cv.string,
            vol.Required("enabled"): cv.boolean,
        }),
    )

    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)
    return True


async def async_unload_entry(hass: HomeAssistant, entry: ConfigEntry):
    """Unload a config entry."""
    unload_ok = await hass.config_entries.async_unload_platforms(entry, PLATFORMS)
    if unload_ok:
        hass.data[DOMAIN].pop(entry.entry_id)
    return unload_ok

"""Config flow for PetLibro Feeder integration."""

import logging
import voluptuous as vol

from homeassistant import config_entries
from homeassistant.core import callback

from .const import DEFAULT_FEEDERS, DOMAIN

_LOGGER = logging.getLogger(__name__)


class PetLibroConfigFlow(config_entries.ConfigFlow, domain=DOMAIN):
    """Handle a config flow for PetLibro Feeder."""

    VERSION = 1

    async def async_step_user(self, user_input=None):
        """Handle initial step."""
        if self._async_current_entries():
            return self.async_abort(reason="already_configured")

        if user_input is not None:
            return self.async_create_entry(title="PetLibro Feeders", data={"feeders": DEFAULT_FEEDERS})

        return self.async_show_form(
            step_id="user",
            data_schema=vol.Schema({}),
            description_placeholders={"info": "Click Submit to initialize PetLibro feeders."},
        )

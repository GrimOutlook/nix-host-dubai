"""Constants for the PetLibro Feeder integration."""

DOMAIN = "petlibro"

# Default feeder configurations from nix/hosts/dubai
DEFAULT_FEEDERS = [
    {
        "name": "feed-jem",
        "device_id": "AF0601030298F0C1320D",
    },
    {
        "name": "feed-willow",
        "device_id": "AF0600310007DF0B19802Q",
    },
    {
        "name": "feed-fern",
        "device_id": "AF06013A96214C47U",
    },
]

# MQTT Topic Patterns
# dl/PLAF301/{device_id}/device/{leaf}
TOPIC_SUB_PATTERN = "dl/PLAF301/{device_id}/device/service/sub"
TOPIC_HEART_POST_PATTERN = "dl/PLAF301/{device_id}/device/heart/post"
TOPIC_EVENT_POST_PATTERN = "dl/PLAF301/{device_id}/device/event/post"
TOPIC_SERVICE_POST_PATTERN = "dl/PLAF301/{device_id}/device/service/post"

# Storage key for pet and schedule persistence
STORAGE_KEY_PETS = "petlibro_pets"
STORAGE_KEY_SCHEDULES = "petlibro_schedules"
STORAGE_VERSION = 1

# The PLAF301's native feeding-plan protocol addresses plans by
# channelPlanNum; the PetLibro app exposes up to 10 per day, so that's the
# cap used here too.
MAX_SCHEDULES_PER_FEEDER = 10

# Commands
CMD_MANUAL_FEEDING = "MANUAL_FEEDING_SERVICE"
CMD_FEEDING_PLAN = "DEVICE_FEEDING_PLAN_SERVICE"
CMD_SWITCH_DOOR = "SWITCH_DOOR_SERVICE"
CMD_ATTR_SET = "ATTR_SET_SERVICE"
CMD_ATTR_GET = "ATTR_GET_SERVICE"
CMD_DEVICE_PROPERTIES = "DEVICE_PROPERTIES_SERVICE"
CMD_DISCOVERY_RFID = "DISCOVERY_RFID_SERVICE"
CMD_DISCOVERY_STOP = "DISCOVERY_STOP_SERVICE"
CMD_ADD_OR_UPDATE_RFID = "ADD_OR_UPDATE_RFID_SERVICE"
CMD_DEL_RFID = "DEL_RFID_SERVICE"
CMD_UNBIND_PET = "UNBIND_PET_SERVICE"
CMD_DISPLAY_MATRIX = "DISPLAY_MATRIX_SERVICE"

# Services
SERVICE_FEED = "feed"
SERVICE_ASSIGN_COLLAR = "assign_collar"
SERVICE_SET_SCHEDULE = "set_schedule"
SERVICE_ADD_SCHEDULE = "add_schedule"
SERVICE_DELETE_SCHEDULE = "delete_schedule"
SERVICE_SYNC_SCHEDULES = "sync_schedules"
SERVICE_SET_SCHEDULE_ENABLED = "set_schedule_enabled"

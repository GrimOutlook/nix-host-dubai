{
  disko.devices.disk.nvme = {
    type = "disk";
    device = "/dev/nvme0n1";
    content = {
      type = "gpt";
      partitions = {
        firmware = {
          size = "256M";
          type = "EF00"; # EFI System / FAT32
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot/firmware";
          };
        };
        boot = {
          size = "512M";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/boot";
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}

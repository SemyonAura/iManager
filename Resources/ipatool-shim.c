// Подменяет MAC-адрес, который ipatool-cpp читает из IOKit.
//
// ipatool выводит из MAC идентификатор устройства (GUID), и Apple запоминает
// этот GUID как доверенное устройство. Пока GUID не меняется, повторный вход
// в Apple ID проходит без кода 2FA — даже после `auth revoke`. Новый MAC
// заставляет Apple увидеть новое устройство и снова запросить код.
//
// Значение задаётся переменной окружения IMANAGER_DEVICE_MAC (12 hex-цифр).
// Если переменная не задана, поведение ipatool не меняется.

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Публичные заголовки macOS не объявляют DYLD_INTERPOSE — определяем сами.
#ifndef DYLD_INTERPOSE
#define DYLD_INTERPOSE(_replacement, _replacee)                                \
    __attribute__((used)) static struct {                                      \
        const void *replacement;                                               \
        const void *replacee;                                                  \
    } _interpose_##_replacee __attribute__((section("__DATA,__interpose"))) = {\
        (const void *)(unsigned long)&_replacement,                            \
        (const void *)(unsigned long)&_replacee                                \
    };
#endif

static CFTypeRef imanager_search_property(io_registry_entry_t entry,
                                          const io_name_t plane,
                                          CFStringRef key,
                                          CFAllocatorRef allocator,
                                          IOOptionBits options) {
    if (key != NULL && CFEqual(key, CFSTR("IOMACAddress"))) {
        const char *hex = getenv("IMANAGER_DEVICE_MAC");
        if (hex != NULL && strlen(hex) == 12) {
            uint8_t bytes[6];
            int valid = 1;

            for (int i = 0; i < 6; i++) {
                unsigned value = 0;
                if (sscanf(hex + i * 2, "%2x", &value) != 1) {
                    valid = 0;
                    break;
                }
                bytes[i] = (uint8_t)value;
            }

            if (valid) {
                return CFDataCreate(allocator, bytes, 6);
            }
        }
    }

    return IORegistryEntrySearchCFProperty(entry, plane, key, allocator, options);
}

DYLD_INTERPOSE(imanager_search_property, IORegistryEntrySearchCFProperty)

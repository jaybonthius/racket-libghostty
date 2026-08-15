#lang racket/base
#|review: ignore|#

(require ffi/unsafe)

(provide _GhosttyDeviceAttributesPrimary
         _GhosttyDeviceAttributesSecondary
         _GhosttyDeviceAttributesTertiary
         _GhosttyDeviceAttributes)

(define-cstruct _GhosttyDeviceAttributesPrimary
                ([conformance-level _uint16] [features (_array _uint16 64)] [num-features _size]))
(define-cstruct _GhosttyDeviceAttributesSecondary
                ([device-type _uint16] [firmware-version _uint16] [rom-cartridge _uint16]))
(define-cstruct _GhosttyDeviceAttributesTertiary ([unit-id _uint32]))
(define-cstruct _GhosttyDeviceAttributes
                ([primary _GhosttyDeviceAttributesPrimary]
                 [secondary _GhosttyDeviceAttributesSecondary]
                 [tertiary _GhosttyDeviceAttributesTertiary]))

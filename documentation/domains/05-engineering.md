# Engineering Domain

**CSIA Area:** System Development Lifecycle
**Module:** `GnomeHub.Engineering`
**Purpose:** Assets, BOMs, parts catalog, vendors, control templates

---

## Overview

The Engineering domain handles all technical aspects: customer assets (PLCs, panels), bills of materials, the master parts catalog, vendor management, and reusable control logic templates. This is where the "controls integrator" expertise lives.

---

## Resources

### Asset
Customer equipment tracked for service and documentation.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| tag | string | yes | Asset tag (e.g., PLC-01) |
| name | string | yes | Asset name |
| description | string | no | Details |
| asset_type | atom | yes | Equipment type |
| manufacturer | string | no | Manufacturer |
| model | string | no | Model number |
| serial_number | string | no | Serial number |
| firmware_version | string | no | Firmware |
| ip_address | string | no | Network IP |
| status | atom | yes | Asset status |
| location | string | no | Physical location |
| install_date | date | no | Installation date |
| warranty_expires | date | no | Warranty end |
| company_id | uuid | yes | Owner company |
| plant_id | uuid | no | Parent plant |
| parent_id | uuid | no | Parent asset |

**Asset Type Values:**
- `:controller` - PLC/DDC controller
- `:io_module` - I/O module
- `:hmi` - HMI panel
- `:drive` - VFD/servo drive
- `:sensor` - Sensor/transmitter
- `:actuator` - Valve/damper actuator
- `:gateway` - Protocol gateway
- `:server` - Server/workstation
- `:panel` - Control panel
- `:network` - Network equipment

**Status Values:**
- `:planned` - Not yet installed
- `:active` - In operation
- `:maintenance` - Under service
- `:offline` - Temporarily offline
- `:decommissioned` - Removed

### Plant
Customer facilities/sites.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| name | string | yes | Plant name |
| code | string | yes | Short code |
| plant_type | atom | yes | Facility type |
| address | string | no | Full address |
| timezone | string | no | Local timezone |
| company_id | uuid | yes | Owner company |

**Plant Type Values:**
- `:manufacturing` - Manufacturing facility
- `:warehouse` - Warehouse/distribution
- `:office` - Office building
- `:data_center` - Data center
- `:water` - Water/wastewater
- `:food` - Food/beverage

---

## Parts Catalog

### Part
Master parts database — critical for estimating and BOMs.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| part_number | string | yes | Internal part number |
| manufacturer_pn | string | no | Manufacturer P/N |
| manufacturer | string | yes | Manufacturer name |
| description | string | yes | Part description |
| category | atom | yes | Part category |
| unit | string | yes | Unit of measure |
| list_price | decimal | no | MSRP |
| our_cost | decimal | no | Our typical cost |
| lead_time_days | integer | no | Typical lead time |
| datasheet_url | string | no | Datasheet link |
| notes | string | no | Internal notes |
| active | boolean | yes | Available for use |

**Category Values:**
- `:controller` - PLCs, PACs
- `:io` - I/O modules, cards
- `:hmi` - HMI panels, displays
- `:drive` - VFDs, servo drives
- `:sensor` - Sensors, transmitters
- `:actuator` - Valves, actuators
- `:power` - Power supplies
- `:network` - Switches, gateways
- `:enclosure` - Enclosures, panels
- `:wire` - Wire, cable, conduit
- `:terminal` - Terminals, connectors
- `:software` - Software licenses

**Example Parts:**
```
1756-L83E    | Rockwell   | ControlLogix L83E Controller
1756-IF16    | Rockwell   | 16-Ch Analog Input Module
IC695CPU315  | Emerson    | RX3i CPU315 Controller
6AV2124-0MC01| Siemens    | TP1200 Comfort Panel
```

### Vendor
Supplier management.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| name | string | yes | Vendor name |
| code | string | yes | Short code |
| vendor_type | atom | yes | Vendor type |
| website | string | no | Website URL |
| account_number | string | no | Our account # |
| contact_name | string | no | Primary contact |
| contact_email | string | no | Contact email |
| contact_phone | string | no | Contact phone |
| payment_terms | string | no | Net 30, etc. |
| notes | string | no | Notes |

**Vendor Type Values:**
- `:distributor` - Distributor (Rexel, WESCO)
- `:manufacturer` - Direct from mfr
- `:rep` - Manufacturer rep

**Common Vendors:**
```
Rexel       | Distributor | Rockwell, misc
WESCO       | Distributor | General electrical
Kele        | Distributor | BAS/HVAC specialty
AutomationDirect | Direct | Budget PLCs
```

### VendorPart
Vendor-specific pricing and lead times.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| vendor_part_number | string | no | Vendor's P/N |
| unit_cost | decimal | yes | Price from vendor |
| lead_time_days | integer | no | Lead time |
| min_quantity | integer | no | Minimum order |
| is_preferred | boolean | yes | Preferred source |
| last_quoted_at | date | no | Last quote date |
| part_id | uuid | yes | Part |
| vendor_id | uuid | yes | Vendor |

---

## Bill of Materials

### BOM
Bills of materials for projects.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| name | string | yes | BOM name |
| description | string | no | BOM description |
| status | atom | yes | BOM status |
| total_cost | decimal | calc | Total material cost |
| project_id | uuid | no | Related project |
| created_by_id | uuid | yes | Author |

**Status Values:**
- `:draft` - Being created
- `:review` - Under review
- `:approved` - Ready to order
- `:ordered` - PO issued
- `:received` - Materials in hand
- `:installed` - In the field

### BOMItem
Line items on BOMs.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| position | integer | yes | Sort order |
| quantity | decimal | yes | Quantity needed |
| unit_cost | decimal | yes | Cost per unit |
| extended_cost | decimal | calc | Line total |
| notes | string | no | Item notes |
| bom_id | uuid | yes | Parent BOM |
| part_id | uuid | yes | Part reference |
| vendor_part_id | uuid | no | Source vendor |

---

## Logic Templates

### LogicTemplate
Reusable control code templates.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uuid | auto | Primary key |
| name | string | yes | Template name |
| description | string | no | Purpose |
| category | atom | yes | Template category |
| platform | atom | yes | Target platform |
| version | string | no | Version |
| code | string | yes | Template code |
| parameters | map | no | Configurable params |
| documentation | string | no | Usage docs |
| author_id | uuid | yes | Creator |

**Category Values:**
- `:hvac` - HVAC control
- `:process` - Process control
- `:motion` - Motion control
- `:safety` - Safety systems
- `:utility` - Utility functions

**Platform Values:**
- `:studio5000` - Rockwell Studio 5000
- `:twincat` - Beckhoff TwinCAT
- `:ignition` - Ignition scripting
- `:generic` - Platform agnostic

---

## Relationships

```
Company (Sales)
    └── Plant
        └── Asset
            └── Asset (nested)

Project (Projects)
    └── BOM
        └── BOMItem
            └── Part
                └── VendorPart
                    └── Vendor
```

---

## UI Routes

| Route | Description |
|-------|-------------|
| `/assets` | Asset list |
| `/assets/:id` | Asset detail |
| `/plants` | Plant list |
| `/parts` | Parts catalog |
| `/parts/:id` | Part detail |
| `/vendors` | Vendor list |
| `/boms` | BOM list |
| `/boms/:id` | BOM detail |
| `/templates` | Logic templates |

---

## File Structure

```
lib/gnome_hub/
├── engineering.ex
└── engineering/
    ├── asset.ex
    ├── plant.ex
    ├── part.ex
    ├── vendor.ex
    ├── vendor_part.ex
    ├── bom.ex
    ├── bom_item.ex
    └── logic_template.ex
```

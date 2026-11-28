use std::collections::{HashMap, HashSet};
use std::ffi::c_void;
use std::panic::{catch_unwind, AssertUnwindSafe};

const SCHEMA_VERSION: u32 = 1;
const MAXIMUM_ROWS: usize = 250_000;
const MAXIMUM_FIELDS_PER_ROW: usize = 16;
const MAXIMUM_TOTAL_FIELDS: usize = 1_000_000;
const MAXIMUM_ORGANIZATION_SCALARS: usize = 256;

const ERROR_WRONG_FILE_COUNT: i32 = 1;
const ERROR_FILE_TOO_LARGE: i32 = 2;
const ERROR_TOTAL_SIZE_EXCEEDED: i32 = 3;
const ERROR_INVALID_ENCODING: i32 = 4;
const ERROR_MALFORMED_CSV: i32 = 5;
const ERROR_MISSING_COLUMNS: i32 = 6;
const ERROR_MIXED_REGISTRIES: i32 = 7;
const ERROR_DUPLICATE_REGISTRY: i32 = 8;
const ERROR_MISSING_REGISTRY: i32 = 9;
const ERROR_INVALID_ASSIGNMENT: i32 = 10;
const ERROR_INVALID_ORGANIZATION: i32 = 11;
const ERROR_TOO_FEW_RECORDS: i32 = 12;
const ERROR_CANCELLED: i32 = 13;

const CANCEL_ROUTINE: i32 = 0;
const CANCEL_RECORDS: i32 = 1;
const CANCEL_BEFORE_FINAL_SORT: i32 = 2;
const CANCEL_AFTER_FINAL_SORT: i32 = 3;

const SOURCE_IEEE_DOWNLOAD: i32 = 1;
const SOURCE_MANUAL_IMPORT: i32 = 2;

const LOOKUP_INVALID: i32 = 0;
const LOOKUP_UNKNOWN: i32 = 1;
const LOOKUP_LOCALLY_ADMINISTERED: i32 = 2;
const LOOKUP_REGISTERED: i32 = 3;

#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash)]
pub enum MacVendorRegistry {
    MaL,
    MaM,
    MaS,
    Iab,
}

impl MacVendorRegistry {
    pub const ALL: [Self; 4] = [Self::MaL, Self::MaM, Self::MaS, Self::Iab];

    pub fn raw_name(self) -> &'static str {
        match self {
            Self::MaL => "MA-L",
            Self::MaM => "MA-M",
            Self::MaS => "MA-S",
            Self::Iab => "IAB",
        }
    }

    pub fn prefix_length_bits(self) -> u32 {
        match self {
            Self::MaL => 24,
            Self::MaM => 28,
            Self::MaS | Self::Iab => 36,
        }
    }

    pub fn code(self) -> i32 {
        match self {
            Self::MaL => 1,
            Self::MaM => 2,
            Self::MaS => 3,
            Self::Iab => 4,
        }
    }

    pub fn from_code(code: i32) -> Result<Self, i32> {
        match code {
            1 => Ok(Self::MaL),
            2 => Ok(Self::MaM),
            3 => Ok(Self::MaS),
            4 => Ok(Self::Iab),
            _ => Err(crate::WIFI_LENS_STATUS_INVALID_MAC_VENDOR_INPUT),
        }
    }

    fn from_raw(value: &str) -> Option<Self> {
        Self::ALL
            .into_iter()
            .find(|registry| registry.raw_name() == value)
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum MacVendorDatabaseSource {
    IeeeDownload,
    ManualImport,
}

impl MacVendorDatabaseSource {
    pub fn code(self) -> i32 {
        match self {
            Self::IeeeDownload => SOURCE_IEEE_DOWNLOAD,
            Self::ManualImport => SOURCE_MANUAL_IMPORT,
        }
    }

    pub fn from_code(code: i32) -> Result<Self, i32> {
        match code {
            SOURCE_IEEE_DOWNLOAD => Ok(Self::IeeeDownload),
            SOURCE_MANUAL_IMPORT => Ok(Self::ManualImport),
            _ => Err(crate::WIFI_LENS_STATUS_INVALID_MAC_VENDOR_INPUT),
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum MacVendorCancellationPoint {
    Routine,
    Records(usize),
    BeforeFinalSort,
    AfterFinalSort,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct MacVendorRegistryInput<'a> {
    pub display_name: &'a str,
    pub data: &'a [u8],
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct MacVendorEntry {
    pub prefix: String,
    pub prefix_length_bits: u32,
    pub organization: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct MacVendorRegistryMetadata {
    pub registry: MacVendorRegistry,
    pub valid_record_count: usize,
    pub sha256: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct MacVendorDatabase {
    pub schema_version: u32,
    pub registries: Vec<MacVendorRegistryMetadata>,
    pub entries: Vec<MacVendorEntry>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum MacVendorLookup {
    Invalid,
    Unknown,
    LocallyAdministered,
    Registered,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum MacVendorError {
    Cancelled,
    WrongFileCount {
        expected: usize,
        actual: usize,
    },
    FileTooLarge {
        file: String,
        maximum_bytes: usize,
    },
    TotalSizeExceeded {
        maximum_bytes: usize,
    },
    InvalidEncoding {
        file: String,
    },
    MalformedCsv {
        file: String,
    },
    MissingColumns {
        file: String,
        columns: Vec<String>,
    },
    MixedRegistries {
        file: String,
    },
    DuplicateRegistry(MacVendorRegistry),
    MissingRegistry(MacVendorRegistry),
    InvalidAssignment {
        file: String,
        registry: MacVendorRegistry,
        assignment: String,
    },
    InvalidOrganization {
        file: String,
    },
    TooFewRecords {
        registry: MacVendorRegistry,
        minimum: usize,
        actual: usize,
    },
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct ParsedRegistry {
    registry: MacVendorRegistry,
    valid_record_count: usize,
    sha256: String,
}

fn is_unicode_format(character: char) -> bool {
    matches!(
        character,
        '\u{00ad}'
            | '\u{0600}'..='\u{0605}'
            | '\u{061c}'
            | '\u{06dd}'
            | '\u{070f}'
            | '\u{180e}'
            | '\u{200b}'..='\u{200f}'
            | '\u{202a}'..='\u{202e}'
            | '\u{2060}'..='\u{2064}'
            | '\u{2066}'..='\u{206f}'
            | '\u{feff}'
            | '\u{fff9}'..='\u{fffb}'
            | '\u{110bd}'
            | '\u{110cd}'
            | '\u{13430}'..='\u{1343f}'
            | '\u{1bca0}'..='\u{1bca3}'
            | '\u{1d173}'..='\u{1d17a}'
            | '\u{e0001}'
            | '\u{e0020}'..='\u{e007f}'
    )
}

fn minimum_for(registry: MacVendorRegistry, minimums: &[(MacVendorRegistry, usize)]) -> usize {
    minimums
        .iter()
        .find(|(candidate, _)| *candidate == registry)
        .map_or(0, |(_, minimum)| *minimum)
}

fn parse_csv<F>(
    text: &str,
    file: &str,
    cancellation_check: &F,
) -> Result<Vec<Vec<String>>, MacVendorError>
where
    F: Fn(MacVendorCancellationPoint) -> Result<(), MacVendorError>,
{
    let characters: Vec<char> = text.chars().collect();
    let mut rows: Vec<Vec<String>> = Vec::new();
    let mut row: Vec<String> = Vec::new();
    let mut field = String::new();
    let mut total_fields = 0usize;
    let mut inside_quotes = false;
    let mut after_closing_quote = false;
    let mut ended_with_terminator = false;
    let mut index = 0usize;

    let append_field = |row: &mut Vec<String>,
                        field: &mut String,
                        total_fields: &mut usize|
     -> Result<(), MacVendorError> {
        if row.len() >= MAXIMUM_FIELDS_PER_ROW || *total_fields >= MAXIMUM_TOTAL_FIELDS {
            return Err(MacVendorError::MalformedCsv {
                file: file.to_string(),
            });
        }
        row.push(std::mem::take(field));
        *total_fields += 1;
        Ok(())
    };

    let append_row =
        |rows: &mut Vec<Vec<String>>, row: &mut Vec<String>| -> Result<(), MacVendorError> {
            if rows.len() >= MAXIMUM_ROWS {
                return Err(MacVendorError::MalformedCsv {
                    file: file.to_string(),
                });
            }
            rows.push(std::mem::take(row));
            if rows.len().is_multiple_of(1_000) {
                cancellation_check(MacVendorCancellationPoint::Records(rows.len()))?;
            }
            Ok(())
        };

    while index < characters.len() {
        let character = characters[index];
        let next_index = index + 1;

        if inside_quotes {
            if character == '"' {
                if next_index < characters.len() && characters[next_index] == '"' {
                    field.push('"');
                    ended_with_terminator = false;
                    index += 2;
                    continue;
                }
                inside_quotes = false;
                after_closing_quote = true;
            } else {
                field.push(character);
            }
            ended_with_terminator = false;
            index = next_index;
            continue;
        }

        if after_closing_quote && !matches!(character, ',' | '\r' | '\n') {
            return Err(MacVendorError::MalformedCsv {
                file: file.to_string(),
            });
        }

        match character {
            '"' => {
                if !field.is_empty() {
                    return Err(MacVendorError::MalformedCsv {
                        file: file.to_string(),
                    });
                }
                inside_quotes = true;
                ended_with_terminator = false;
            }
            ',' => {
                append_field(&mut row, &mut field, &mut total_fields)?;
                after_closing_quote = false;
                ended_with_terminator = false;
            }
            '\r' | '\n' => {
                append_field(&mut row, &mut field, &mut total_fields)?;
                append_row(&mut rows, &mut row)?;
                after_closing_quote = false;
                ended_with_terminator = true;
                if character == '\r'
                    && next_index < characters.len()
                    && characters[next_index] == '\n'
                {
                    index += 2;
                    continue;
                }
            }
            _ => {
                field.push(character);
                ended_with_terminator = false;
            }
        }
        index = next_index;
    }

    if inside_quotes {
        return Err(MacVendorError::MalformedCsv {
            file: file.to_string(),
        });
    }
    if !ended_with_terminator {
        append_field(&mut row, &mut field, &mut total_fields)?;
        append_row(&mut rows, &mut row)?;
    }
    Ok(rows)
}

fn decode_entity(entity: &str) -> Option<char> {
    match entity {
        "amp" => Some('&'),
        "lt" => Some('<'),
        "gt" => Some('>'),
        "quot" => Some('"'),
        "#39" => Some('\''),
        _ => {
            if let Some(hex) = entity
                .strip_prefix("#x")
                .or_else(|| entity.strip_prefix("#X"))
            {
                u32::from_str_radix(hex, 16).ok().and_then(char::from_u32)
            } else if let Some(decimal) = entity.strip_prefix('#') {
                decimal.parse::<u32>().ok().and_then(char::from_u32)
            } else {
                None
            }
        }
    }
}

fn decode_entities(value: &str) -> String {
    let characters: Vec<char> = value.chars().collect();
    let mut result = String::new();
    let mut index = 0usize;
    while index < characters.len() {
        if characters[index] != '&' {
            result.push(characters[index]);
            index += 1;
            continue;
        }
        let entity_start = index + 1;
        let mut cursor = entity_start;
        let mut candidate = String::new();
        let mut decoded = None;
        let mut next_index = entity_start;
        while cursor < characters.len() {
            let character = characters[cursor];
            if character == '&' {
                break;
            }
            if character == ';' {
                decoded = decode_entity(&candidate);
                next_index = cursor + 1;
                break;
            }
            if candidate.chars().count() >= 8 {
                break;
            }
            candidate.push(character);
            cursor += 1;
        }
        if let Some(scalar) = decoded {
            result.push(scalar);
            index = next_index;
        } else {
            result.push('&');
            index = entity_start;
        }
    }
    result
}

fn normalize_organization(file: &str, value: &str) -> Result<Option<String>, MacVendorError> {
    let decoded = decode_entities(value);
    let mut normalized = String::new();
    let mut pending_space = false;
    for character in decoded.chars() {
        if character.is_whitespace() {
            pending_space = !normalized.is_empty();
            continue;
        }
        if character.is_control() {
            return Err(MacVendorError::InvalidOrganization {
                file: file.to_string(),
            });
        }
        if pending_space {
            normalized.push(' ');
            pending_space = false;
        }
        normalized.push(character);
    }
    if normalized.chars().count() > MAXIMUM_ORGANIZATION_SCALARS {
        return Err(MacVendorError::InvalidOrganization {
            file: file.to_string(),
        });
    }
    if normalized.is_empty() || normalized.eq_ignore_ascii_case("private") {
        return Ok(None);
    }
    Ok(Some(normalized))
}

fn normalize_assignment(value: &str) -> String {
    value
        .chars()
        .filter(|character| *character != ':' && *character != '-')
        .flat_map(char::to_uppercase)
        .collect()
}

fn is_hex_assignment(value: &str, expected_length: usize) -> bool {
    value.len() == expected_length
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'A'..=b'F').contains(&byte))
}

fn parse_registry<F>(
    input: &MacVendorRegistryInput<'_>,
    minimums: &[(MacVendorRegistry, usize)],
    cancellation_check: &F,
) -> Result<(ParsedRegistry, Vec<MacVendorEntry>), MacVendorError>
where
    F: Fn(MacVendorCancellationPoint) -> Result<(), MacVendorError>,
{
    cancellation_check(MacVendorCancellationPoint::Routine)?;
    let text = std::str::from_utf8(input.data).map_err(|_| MacVendorError::InvalidEncoding {
        file: input.display_name.to_string(),
    })?;
    let text = text.strip_prefix('\u{feff}').unwrap_or(text);
    let filtered: String = text
        .chars()
        .filter(|character| !is_unicode_format(*character))
        .collect();
    let rows = parse_csv(&filtered, input.display_name, cancellation_check)?;
    let header = rows.first().ok_or_else(|| MacVendorError::MalformedCsv {
        file: input.display_name.to_string(),
    })?;

    let required_columns = ["Registry", "Assignment", "Organization Name"];
    let missing_columns: Vec<String> = required_columns
        .iter()
        .filter(|column| !header.iter().any(|value| value == **column))
        .map(|column| (*column).to_string())
        .collect();
    if !missing_columns.is_empty() {
        return Err(MacVendorError::MissingColumns {
            file: input.display_name.to_string(),
            columns: missing_columns,
        });
    }

    let registry_index = header.iter().position(|value| value == "Registry").unwrap();
    let assignment_index = header
        .iter()
        .position(|value| value == "Assignment")
        .unwrap();
    let organization_index = header
        .iter()
        .position(|value| value == "Organization Name")
        .unwrap();
    let greatest_index = registry_index.max(assignment_index).max(organization_index);

    let mut file_registry = None;
    let mut entries_by_assignment: HashMap<(String, u32), MacVendorEntry> = HashMap::new();
    let mut ambiguous = HashSet::new();

    for (index, row) in rows.iter().skip(1).enumerate() {
        if index > 0 && index.is_multiple_of(1_000) {
            cancellation_check(MacVendorCancellationPoint::Records(index))?;
        }
        if row.iter().all(|value| value.trim().is_empty()) {
            continue;
        }
        if row.len() <= greatest_index
            || MacVendorRegistry::from_raw(&row[registry_index]).is_none()
        {
            return Err(MacVendorError::MixedRegistries {
                file: input.display_name.to_string(),
            });
        }
        let registry = MacVendorRegistry::from_raw(&row[registry_index]).unwrap();
        if let Some(existing) = file_registry {
            if existing != registry {
                return Err(MacVendorError::MixedRegistries {
                    file: input.display_name.to_string(),
                });
            }
        } else {
            file_registry = Some(registry);
        }

        let assignment = row[assignment_index].clone();
        let normalized_assignment = normalize_assignment(&assignment);
        let prefix_length_bits = registry.prefix_length_bits();
        if !is_hex_assignment(&normalized_assignment, (prefix_length_bits / 4) as usize) {
            return Err(MacVendorError::InvalidAssignment {
                file: input.display_name.to_string(),
                registry,
                assignment,
            });
        }

        let Some(organization) =
            normalize_organization(input.display_name, &row[organization_index])?
        else {
            continue;
        };
        let key = (normalized_assignment.clone(), prefix_length_bits);
        if ambiguous.contains(&key) {
            continue;
        }
        if let Some(existing) = entries_by_assignment.get(&key) {
            if existing.organization != organization {
                entries_by_assignment.remove(&key);
                ambiguous.insert(key);
            }
        } else {
            entries_by_assignment.insert(
                key,
                MacVendorEntry {
                    prefix: normalized_assignment,
                    prefix_length_bits,
                    organization,
                },
            );
        }
    }

    let registry = file_registry.ok_or_else(|| MacVendorError::MixedRegistries {
        file: input.display_name.to_string(),
    })?;
    let minimum = minimum_for(registry, minimums);
    if entries_by_assignment.len() < minimum {
        return Err(MacVendorError::TooFewRecords {
            registry,
            minimum,
            actual: entries_by_assignment.len(),
        });
    }

    Ok((
        ParsedRegistry {
            registry,
            valid_record_count: entries_by_assignment.len(),
            sha256: sha256_hex(input.data),
        },
        entries_by_assignment.into_values().collect(),
    ))
}

pub fn parse_mac_vendor_database<F>(
    inputs: &[MacVendorRegistryInput<'_>],
    minimum_record_counts: &[(MacVendorRegistry, usize)],
    maximum_file_bytes: usize,
    maximum_total_bytes: usize,
    cancellation_check: F,
) -> Result<MacVendorDatabase, MacVendorError>
where
    F: Fn(MacVendorCancellationPoint) -> Result<(), MacVendorError>,
{
    cancellation_check(MacVendorCancellationPoint::Routine)?;
    if inputs.len() != MacVendorRegistry::ALL.len() {
        return Err(MacVendorError::WrongFileCount {
            expected: MacVendorRegistry::ALL.len(),
            actual: inputs.len(),
        });
    }

    let mut total_bytes = 0usize;
    for input in inputs {
        cancellation_check(MacVendorCancellationPoint::Routine)?;
        if input.data.len() > maximum_file_bytes {
            return Err(MacVendorError::FileTooLarge {
                file: input.display_name.to_string(),
                maximum_bytes: maximum_file_bytes,
            });
        }
        total_bytes += input.data.len();
        if total_bytes > maximum_total_bytes {
            return Err(MacVendorError::TotalSizeExceeded {
                maximum_bytes: maximum_total_bytes,
            });
        }
    }

    let mut parsed_by_registry: HashMap<MacVendorRegistry, ParsedRegistry> = HashMap::new();
    let mut parsed_entries: HashMap<MacVendorRegistry, Vec<MacVendorEntry>> = HashMap::new();
    for input in inputs {
        cancellation_check(MacVendorCancellationPoint::Routine)?;
        let (metadata, entries) =
            parse_registry(input, minimum_record_counts, &cancellation_check)?;
        let registry = metadata.registry;
        if parsed_by_registry.insert(registry, metadata).is_some() {
            return Err(MacVendorError::DuplicateRegistry(registry));
        }
        parsed_entries.insert(registry, entries);
    }
    for registry in MacVendorRegistry::ALL {
        if !parsed_by_registry.contains_key(&registry) {
            return Err(MacVendorError::MissingRegistry(registry));
        }
    }

    let mut entries_by_assignment: HashMap<(String, u32), MacVendorEntry> = HashMap::new();
    let mut ambiguous = HashSet::new();
    for registry in MacVendorRegistry::ALL {
        let Some(entries) = parsed_entries.get(&registry) else {
            continue;
        };
        for (index, entry) in entries.iter().enumerate() {
            if index > 0 && index.is_multiple_of(1_000) {
                cancellation_check(MacVendorCancellationPoint::Records(index))?;
            }
            let key = (entry.prefix.clone(), entry.prefix_length_bits);
            if ambiguous.contains(&key) {
                continue;
            }
            if let Some(existing) = entries_by_assignment.get(&key) {
                if existing.organization != entry.organization {
                    entries_by_assignment.remove(&key);
                    ambiguous.insert(key);
                }
            } else {
                entries_by_assignment.insert(key, entry.clone());
            }
        }
    }

    let registries = MacVendorRegistry::ALL
        .into_iter()
        .map(|registry| {
            parsed_by_registry
                .get(&registry)
                .map(|metadata| MacVendorRegistryMetadata {
                    registry: metadata.registry,
                    valid_record_count: metadata.valid_record_count,
                    sha256: metadata.sha256.clone(),
                })
        })
        .collect::<Option<Vec<_>>>()
        .unwrap_or_default();

    cancellation_check(MacVendorCancellationPoint::BeforeFinalSort)?;
    let mut entries: Vec<MacVendorEntry> = entries_by_assignment.into_values().collect();
    entries.sort_by(|left, right| {
        right
            .prefix_length_bits
            .cmp(&left.prefix_length_bits)
            .then_with(|| left.prefix.cmp(&right.prefix))
    });
    cancellation_check(MacVendorCancellationPoint::AfterFinalSort)?;

    Ok(MacVendorDatabase {
        schema_version: SCHEMA_VERSION,
        registries,
        entries,
    })
}

pub fn normalize_mac_address(mac_address: &str) -> Option<String> {
    if mac_address.len() == 12 && mac_address.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Some(mac_address.to_ascii_uppercase());
    }
    for separator in [':', '-'] {
        let octets: Vec<&str> = mac_address.split(separator).collect();
        if octets.len() == 6
            && octets
                .iter()
                .all(|octet| octet.len() == 2 && octet.bytes().all(|byte| byte.is_ascii_hexdigit()))
        {
            return Some(octets.concat().to_ascii_uppercase());
        }
    }
    None
}

pub fn lookup_mac_vendor(mac_address: &str, entries: &[MacVendorEntry]) -> MacVendorLookup {
    let Some(normalized) = normalize_mac_address(mac_address) else {
        return MacVendorLookup::Invalid;
    };
    let Ok(numeric_address) = u64::from_str_radix(&normalized, 16) else {
        return MacVendorLookup::Invalid;
    };
    let first_octet = (numeric_address >> 40) as u8;
    if numeric_address == 0 || first_octet & 0x01 != 0 {
        return MacVendorLookup::Invalid;
    }
    if first_octet & 0x02 != 0 {
        return MacVendorLookup::LocallyAdministered;
    }
    let indexes = prefix_value_indexes(entries);
    for prefix_length_bits in [36u32, 28, 24] {
        let prefix_value = numeric_address >> (48 - prefix_length_bits);
        if indexes.contains_key(&(prefix_length_bits, prefix_value)) {
            return MacVendorLookup::Registered;
        }
    }
    MacVendorLookup::Unknown
}

pub fn lookup_mac_vendor_organization(
    mac_address: &str,
    entries: &[MacVendorEntry],
) -> Option<String> {
    let normalized = normalize_mac_address(mac_address)?;
    let numeric_address = u64::from_str_radix(&normalized, 16).ok()?;
    let first_octet = (numeric_address >> 40) as u8;
    if numeric_address == 0 || first_octet & 0x01 != 0 || first_octet & 0x02 != 0 {
        return None;
    }
    let indexes = prefix_value_indexes(entries);
    for prefix_length_bits in [36u32, 28, 24] {
        let prefix_value = numeric_address >> (48 - prefix_length_bits);
        if let Some(entry) = indexes
            .get(&(prefix_length_bits, prefix_value))
            .and_then(|index| entries.get(*index))
        {
            return Some(entry.organization.clone());
        }
    }
    None
}

fn prefix_value_indexes(entries: &[MacVendorEntry]) -> HashMap<(u32, u64), usize> {
    let mut indexes = HashMap::with_capacity(entries.len());
    for (index, entry) in entries.iter().enumerate() {
        if let Ok(prefix_value) = u64::from_str_radix(&entry.prefix, 16) {
            indexes
                .entry((entry.prefix_length_bits, prefix_value))
                .or_insert(index);
        }
    }
    indexes
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct WiFiLensMacVendorRegistryInput {
    pub display_name_offset: usize,
    pub display_name_length: usize,
    pub data_offset: usize,
    pub data_length: usize,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct WiFiLensMacVendorMinimum {
    pub registry: i32,
    pub minimum_records: usize,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct WiFiLensMacVendorRegistryMetadata {
    pub registry: i32,
    pub valid_record_count: usize,
    pub sha256_offset: usize,
    pub sha256_length: usize,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct WiFiLensMacVendorEntry {
    pub prefix_offset: usize,
    pub prefix_length: usize,
    pub prefix_length_bits: u32,
    pub organization_offset: usize,
    pub organization_length: usize,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct WiFiLensMacVendorFailure {
    pub code: i32,
    pub registry: i32,
    pub number1: i64,
    pub number2: i64,
    pub file_offset: usize,
    pub file_length: usize,
    pub detail_offset: usize,
    pub detail_length: usize,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct WiFiLensMacVendorLookupEntry {
    pub prefix_offset: usize,
    pub prefix_length: usize,
    pub prefix_length_bits: u32,
    pub organization_offset: usize,
    pub organization_length: usize,
}

pub type WiFiLensMacVendorCancellationCallback =
    Option<unsafe extern "C" fn(point: i32, count: usize, context: *mut c_void) -> i32>;

fn slice_from_buffer<'a>(buffer: &'a [u8], offset: usize, length: usize) -> Result<&'a [u8], i32> {
    let end = offset
        .checked_add(length)
        .ok_or(crate::WIFI_LENS_STATUS_INVALID_INPUT_SLICE)?;
    buffer
        .get(offset..end)
        .ok_or(crate::WIFI_LENS_STATUS_INVALID_INPUT_SLICE)
}

fn str_from_buffer<'a>(buffer: &'a [u8], offset: usize, length: usize) -> Result<&'a str, i32> {
    let bytes = slice_from_buffer(buffer, offset, length)?;
    std::str::from_utf8(bytes).map_err(|_| crate::WIFI_LENS_STATUS_INVALID_UTF8)
}

fn failure_from_error(error: &MacVendorError, detail_offset: usize) -> WiFiLensMacVendorFailure {
    let mut failure = WiFiLensMacVendorFailure::default();
    match error {
        MacVendorError::Cancelled => failure.code = ERROR_CANCELLED,
        MacVendorError::WrongFileCount { expected, actual } => {
            failure.code = ERROR_WRONG_FILE_COUNT;
            failure.number1 = *expected as i64;
            failure.number2 = *actual as i64;
        }
        MacVendorError::FileTooLarge {
            file,
            maximum_bytes,
        } => {
            failure.code = ERROR_FILE_TOO_LARGE;
            failure.number1 = *maximum_bytes as i64;
            failure.detail_offset = detail_offset;
            failure.detail_length = file.len();
        }
        MacVendorError::TotalSizeExceeded { maximum_bytes } => {
            failure.code = ERROR_TOTAL_SIZE_EXCEEDED;
            failure.number1 = *maximum_bytes as i64;
        }
        MacVendorError::InvalidEncoding { file } => {
            failure.code = ERROR_INVALID_ENCODING;
            failure.detail_offset = detail_offset;
            failure.detail_length = file.len();
        }
        MacVendorError::MalformedCsv { file } => {
            failure.code = ERROR_MALFORMED_CSV;
            failure.detail_offset = detail_offset;
            failure.detail_length = file.len();
        }
        MacVendorError::MissingColumns { file, columns } => {
            failure.code = ERROR_MISSING_COLUMNS;
            failure.detail_offset = detail_offset;
            failure.detail_length = file.len();
            let mut mask = 0i64;
            for (index, required) in ["Registry", "Assignment", "Organization Name"]
                .iter()
                .enumerate()
            {
                if columns.iter().any(|column| column == required) {
                    mask |= 1 << index;
                }
            }
            failure.number1 = mask;
        }
        MacVendorError::MixedRegistries { file } => {
            failure.code = ERROR_MIXED_REGISTRIES;
            failure.detail_offset = detail_offset;
            failure.detail_length = file.len();
        }
        MacVendorError::DuplicateRegistry(registry) => {
            failure.code = ERROR_DUPLICATE_REGISTRY;
            failure.registry = registry.code();
        }
        MacVendorError::MissingRegistry(registry) => {
            failure.code = ERROR_MISSING_REGISTRY;
            failure.registry = registry.code();
        }
        MacVendorError::InvalidAssignment {
            file,
            registry,
            assignment,
        } => {
            failure.code = ERROR_INVALID_ASSIGNMENT;
            failure.registry = registry.code();
            failure.detail_offset = detail_offset;
            failure.detail_length = file.len();
            failure.number1 = 0;
            failure.number2 = assignment.len() as i64;
        }
        MacVendorError::InvalidOrganization { file } => {
            failure.code = ERROR_INVALID_ORGANIZATION;
            failure.detail_offset = detail_offset;
            failure.detail_length = file.len();
        }
        MacVendorError::TooFewRecords {
            registry,
            minimum,
            actual,
        } => {
            failure.code = ERROR_TOO_FEW_RECORDS;
            failure.registry = registry.code();
            failure.number1 = *minimum as i64;
            failure.number2 = *actual as i64;
        }
    }
    failure
}

fn failure_detail(error: &MacVendorError) -> Vec<u8> {
    match error {
        MacVendorError::FileTooLarge { file, .. }
        | MacVendorError::InvalidEncoding { file }
        | MacVendorError::MalformedCsv { file }
        | MacVendorError::MixedRegistries { file }
        | MacVendorError::InvalidOrganization { file } => file.as_bytes().to_vec(),
        MacVendorError::MissingColumns { file, .. } => file.as_bytes().to_vec(),
        MacVendorError::InvalidAssignment {
            file, assignment, ..
        } => {
            let mut bytes = file.as_bytes().to_vec();
            bytes.extend_from_slice(assignment.as_bytes());
            bytes
        }
        _ => Vec::new(),
    }
}

fn invoke_cancellation(
    callback: WiFiLensMacVendorCancellationCallback,
    context: *mut c_void,
    point: MacVendorCancellationPoint,
) -> Result<(), MacVendorError> {
    let Some(callback) = callback else {
        return Ok(());
    };
    let (code, count) = match point {
        MacVendorCancellationPoint::Routine => (CANCEL_ROUTINE, 0),
        MacVendorCancellationPoint::Records(count) => (CANCEL_RECORDS, count),
        MacVendorCancellationPoint::BeforeFinalSort => (CANCEL_BEFORE_FINAL_SORT, 0),
        MacVendorCancellationPoint::AfterFinalSort => (CANCEL_AFTER_FINAL_SORT, 0),
    };
    let cancelled = unsafe { callback(code, count, context) };
    if cancelled == 0 {
        Ok(())
    } else {
        Err(MacVendorError::Cancelled)
    }
}

#[no_mangle]
pub unsafe extern "C" fn wifi_lens_mac_vendor_parse_database(
    inputs: *const WiFiLensMacVendorRegistryInput,
    input_count: usize,
    strings: *const u8,
    strings_length: usize,
    source: i32,
    minimums: *const WiFiLensMacVendorMinimum,
    minimum_count: usize,
    maximum_file_bytes: usize,
    maximum_total_bytes: usize,
    cancellation: WiFiLensMacVendorCancellationCallback,
    cancellation_context: *mut c_void,
    failure: *mut WiFiLensMacVendorFailure,
    failure_text: *mut u8,
    failure_text_capacity: usize,
    failure_text_length: *mut usize,
    registries: *mut WiFiLensMacVendorRegistryMetadata,
    registries_capacity: usize,
    entries: *mut WiFiLensMacVendorEntry,
    entries_capacity: usize,
    text: *mut u8,
    text_capacity: usize,
    registries_count: *mut usize,
    entries_count: *mut usize,
    text_length: *mut usize,
) -> i32 {
    if failure.is_null()
        || failure_text_length.is_null()
        || registries_count.is_null()
        || entries_count.is_null()
        || text_length.is_null()
        || (input_count > 0 && inputs.is_null())
        || (strings_length > 0 && strings.is_null())
        || (minimum_count > 0 && minimums.is_null())
        || (failure_text_capacity > 0 && failure_text.is_null())
        || (registries_capacity > 0 && registries.is_null())
        || (entries_capacity > 0 && entries.is_null())
        || (text_capacity > 0 && text.is_null())
    {
        return crate::WIFI_LENS_STATUS_INVALID_POINTER;
    }

    unsafe {
        *failure = WiFiLensMacVendorFailure::default();
        *failure_text_length = 0;
        *registries_count = 0;
        *entries_count = 0;
        *text_length = 0;
    }

    let status = catch_unwind(AssertUnwindSafe(|| {
        let strings = if strings_length == 0 {
            &[]
        } else {
            unsafe { std::slice::from_raw_parts(strings, strings_length) }
        };
        let raw_inputs = if input_count == 0 {
            &[]
        } else {
            unsafe { std::slice::from_raw_parts(inputs, input_count) }
        };
        let _source = MacVendorDatabaseSource::from_code(source)?;
        if minimum_count < MacVendorRegistry::ALL.len() {
            return Err(crate::WIFI_LENS_STATUS_INVALID_MAC_VENDOR_INPUT);
        }
        let raw_minimums = unsafe { std::slice::from_raw_parts(minimums, minimum_count) };
        let mut minimums = Vec::with_capacity(MacVendorRegistry::ALL.len());
        for minimum in raw_minimums.iter().take(MacVendorRegistry::ALL.len()) {
            minimums.push((
                MacVendorRegistry::from_code(minimum.registry)?,
                minimum.minimum_records,
            ));
        }

        let mut parsed_inputs = Vec::with_capacity(raw_inputs.len());
        for raw in raw_inputs {
            parsed_inputs.push(MacVendorRegistryInput {
                display_name: str_from_buffer(
                    strings,
                    raw.display_name_offset,
                    raw.display_name_length,
                )?,
                data: slice_from_buffer(strings, raw.data_offset, raw.data_length)?,
            });
        }

        let database = parse_mac_vendor_database(
            &parsed_inputs,
            &minimums,
            maximum_file_bytes,
            maximum_total_bytes,
            |point| invoke_cancellation(cancellation, cancellation_context, point),
        )
        .map_err(|error| {
            let detail = failure_detail(&error);
            let detail_offset = 0;
            let mut failure_value = failure_from_error(&error, detail_offset);
            unsafe {
                *failure_text_length = detail.len();
            }
            if detail.len() <= failure_text_capacity && !detail.is_empty() {
                unsafe {
                    std::ptr::copy_nonoverlapping(detail.as_ptr(), failure_text, detail.len());
                }
            }
            unsafe {
                *failure = failure_value;
            }
            crate::WIFI_LENS_STATUS_INVALID_MAC_VENDOR_INPUT
        })?;

        let mut output_text = Vec::new();
        let mut registry_outputs = Vec::with_capacity(database.registries.len());
        for metadata in &database.registries {
            let offset = output_text.len();
            output_text.extend_from_slice(metadata.sha256.as_bytes());
            registry_outputs.push(WiFiLensMacVendorRegistryMetadata {
                registry: metadata.registry.code(),
                valid_record_count: metadata.valid_record_count,
                sha256_offset: offset,
                sha256_length: metadata.sha256.len(),
            });
        }
        let mut entry_outputs = Vec::with_capacity(database.entries.len());
        for entry in &database.entries {
            let prefix_offset = output_text.len();
            output_text.extend_from_slice(entry.prefix.as_bytes());
            let organization_offset = output_text.len();
            output_text.extend_from_slice(entry.organization.as_bytes());
            entry_outputs.push(WiFiLensMacVendorEntry {
                prefix_offset,
                prefix_length: entry.prefix.len(),
                prefix_length_bits: entry.prefix_length_bits,
                organization_offset,
                organization_length: entry.organization.len(),
            });
        }

        unsafe {
            *registries_count = registry_outputs.len();
            *entries_count = entry_outputs.len();
            *text_length = output_text.len();
        }
        if registries_capacity < registry_outputs.len()
            || entries_capacity < entry_outputs.len()
            || text_capacity < output_text.len()
        {
            return Err(crate::WIFI_LENS_STATUS_OUTPUT_TOO_SMALL);
        }
        if !registry_outputs.is_empty() {
            unsafe {
                std::ptr::copy_nonoverlapping(
                    registry_outputs.as_ptr(),
                    registries,
                    registry_outputs.len(),
                );
            }
        }
        if !entry_outputs.is_empty() {
            unsafe {
                std::ptr::copy_nonoverlapping(entry_outputs.as_ptr(), entries, entry_outputs.len());
            }
        }
        if !output_text.is_empty() {
            unsafe {
                std::ptr::copy_nonoverlapping(output_text.as_ptr(), text, output_text.len());
            }
        }
        Ok(crate::WIFI_LENS_STATUS_OK)
    }));

    match status {
        Ok(Ok(status)) => status,
        Ok(Err(status)) => status,
        Err(_) => crate::WIFI_LENS_STATUS_PANIC,
    }
}

#[no_mangle]
pub unsafe extern "C" fn wifi_lens_mac_vendor_lookup(
    mac_address: *const u8,
    mac_address_length: usize,
    entries: *const WiFiLensMacVendorLookupEntry,
    entry_count: usize,
    strings: *const u8,
    strings_length: usize,
    organization: *mut u8,
    organization_capacity: usize,
    organization_length: *mut usize,
    result_code: *mut i32,
) -> i32 {
    if result_code.is_null()
        || organization_length.is_null()
        || (mac_address_length > 0 && mac_address.is_null())
        || (entry_count > 0 && entries.is_null())
        || (strings_length > 0 && strings.is_null())
        || (organization_capacity > 0 && organization.is_null())
    {
        return crate::WIFI_LENS_STATUS_INVALID_POINTER;
    }
    unsafe {
        *result_code = LOOKUP_INVALID;
        *organization_length = 0;
    }

    let status = catch_unwind(AssertUnwindSafe(|| {
        let mac = str_from_buffer(
            if mac_address_length == 0 {
                &[]
            } else {
                unsafe { std::slice::from_raw_parts(mac_address, mac_address_length) }
            },
            0,
            mac_address_length,
        )?;
        let strings = if strings_length == 0 {
            &[]
        } else {
            unsafe { std::slice::from_raw_parts(strings, strings_length) }
        };
        let raw_entries = if entry_count == 0 {
            &[]
        } else {
            unsafe { std::slice::from_raw_parts(entries, entry_count) }
        };
        let mut parsed_entries = Vec::with_capacity(raw_entries.len());
        for raw in raw_entries {
            parsed_entries.push(MacVendorEntry {
                prefix: str_from_buffer(strings, raw.prefix_offset, raw.prefix_length)?.to_string(),
                prefix_length_bits: raw.prefix_length_bits,
                organization: str_from_buffer(
                    strings,
                    raw.organization_offset,
                    raw.organization_length,
                )?
                .to_string(),
            });
        }

        let result = lookup_mac_vendor(mac, &parsed_entries);
        let code = match result {
            MacVendorLookup::Invalid => LOOKUP_INVALID,
            MacVendorLookup::Unknown => LOOKUP_UNKNOWN,
            MacVendorLookup::LocallyAdministered => LOOKUP_LOCALLY_ADMINISTERED,
            MacVendorLookup::Registered => LOOKUP_REGISTERED,
        };
        unsafe { *result_code = code };
        if result == MacVendorLookup::Registered {
            let Some(organization_value) = lookup_mac_vendor_organization(mac, &parsed_entries)
            else {
                return Err(crate::WIFI_LENS_STATUS_INVALID_MAC_VENDOR_INPUT);
            };
            unsafe { *organization_length = organization_value.len() };
            if organization_value.len() > organization_capacity {
                return Err(crate::WIFI_LENS_STATUS_OUTPUT_TOO_SMALL);
            }
            if !organization_value.is_empty() {
                unsafe {
                    std::ptr::copy_nonoverlapping(
                        organization_value.as_ptr(),
                        organization,
                        organization_value.len(),
                    );
                }
            }
        }
        Ok(crate::WIFI_LENS_STATUS_OK)
    }));

    match status {
        Ok(Ok(status)) => status,
        Ok(Err(status)) => status,
        Err(_) => crate::WIFI_LENS_STATUS_PANIC,
    }
}

/// An owned, reusable index. Input buffers passed to the builder may be released
/// as soon as it returns.
pub struct WiFiLensMacVendorIndex {
    organizations: HashMap<(u32, u64), String>,
    #[cfg(test)]
    index_builds: usize,
}

#[no_mangle]
pub unsafe extern "C" fn wifi_lens_mac_vendor_index_build(
    entries: *const WiFiLensMacVendorLookupEntry,
    entry_count: usize,
    strings: *const u8,
    strings_length: usize,
    out_index: *mut *mut WiFiLensMacVendorIndex,
) -> i32 {
    if out_index.is_null()
        || (entry_count > 0 && entries.is_null())
        || (strings_length > 0 && strings.is_null())
    {
        return crate::WIFI_LENS_STATUS_INVALID_POINTER;
    }
    unsafe {
        *out_index = std::ptr::null_mut();
    }
    match catch_unwind(AssertUnwindSafe(|| -> Result<_, i32> {
        let bytes = if strings_length == 0 {
            &[]
        } else {
            unsafe { std::slice::from_raw_parts(strings, strings_length) }
        };
        let raw = if entry_count == 0 {
            &[]
        } else {
            unsafe { std::slice::from_raw_parts(entries, entry_count) }
        };
        let mut organizations = HashMap::with_capacity(raw.len());
        for entry in raw {
            let prefix = str_from_buffer(bytes, entry.prefix_offset, entry.prefix_length)?;
            let organization =
                str_from_buffer(bytes, entry.organization_offset, entry.organization_length)?;
            let prefix_value = u64::from_str_radix(prefix, 16)
                .map_err(|_| crate::WIFI_LENS_STATUS_INVALID_MAC_VENDOR_INPUT)?;
            if ![24, 28, 36].contains(&entry.prefix_length_bits) {
                return Err(crate::WIFI_LENS_STATUS_INVALID_MAC_VENDOR_INPUT);
            }
            organizations
                .entry((entry.prefix_length_bits, prefix_value))
                .or_insert_with(|| organization.to_owned());
        }
        Ok(Box::into_raw(Box::new(WiFiLensMacVendorIndex {
            organizations,
            #[cfg(test)]
            index_builds: 1,
        })))
    })) {
        Ok(Ok(index)) => {
            unsafe {
                *out_index = index;
            }
            crate::WIFI_LENS_STATUS_OK
        }
        Ok(Err(status)) => status,
        Err(_) => crate::WIFI_LENS_STATUS_PANIC,
    }
}

#[no_mangle]
pub unsafe extern "C" fn wifi_lens_mac_vendor_index_lookup(
    index: *const WiFiLensMacVendorIndex,
    mac: *const u8,
    mac_length: usize,
    organization: *mut u8,
    organization_capacity: usize,
    organization_length: *mut usize,
    result_code: *mut i32,
) -> i32 {
    if index.is_null()
        || organization_length.is_null()
        || result_code.is_null()
        || (mac_length > 0 && mac.is_null())
        || (organization_capacity > 0 && organization.is_null())
    {
        return crate::WIFI_LENS_STATUS_INVALID_POINTER;
    }
    unsafe {
        *organization_length = 0;
        *result_code = LOOKUP_INVALID;
    }
    match catch_unwind(AssertUnwindSafe(|| -> Result<(), i32> {
        let text = if mac_length == 0 {
            &[]
        } else {
            unsafe { std::slice::from_raw_parts(mac, mac_length) }
        };
        let address = str_from_buffer(text, 0, mac_length)?;
        let normalized = normalize_mac_address(address);
        let mut result = LOOKUP_INVALID;
        let mut found = None;
        if let Some(normalized) = normalized {
            let numeric = u64::from_str_radix(&normalized, 16)
                .map_err(|_| crate::WIFI_LENS_STATUS_INVALID_MAC_VENDOR_INPUT)?;
            let first = (numeric >> 40) as u8;
            if numeric != 0 && first & 1 == 0 {
                if first & 2 != 0 {
                    result = LOOKUP_LOCALLY_ADMINISTERED;
                } else {
                    result = LOOKUP_UNKNOWN;
                    let index = unsafe { &*index };
                    for bits in [36, 28, 24] {
                        if let Some(value) =
                            index.organizations.get(&(bits, numeric >> (48 - bits)))
                        {
                            result = LOOKUP_REGISTERED;
                            found = Some(value);
                            break;
                        }
                    }
                }
            }
        }
        unsafe {
            *result_code = result;
        }
        if let Some(value) = found {
            unsafe {
                *organization_length = value.len();
            }
            if value.len() > organization_capacity {
                return Err(crate::WIFI_LENS_STATUS_OUTPUT_TOO_SMALL);
            }
            if !value.is_empty() {
                unsafe {
                    std::ptr::copy_nonoverlapping(value.as_ptr(), organization, value.len());
                }
            }
        }
        Ok(())
    })) {
        Ok(Ok(())) => crate::WIFI_LENS_STATUS_OK,
        Ok(Err(e)) => e,
        Err(_) => crate::WIFI_LENS_STATUS_PANIC,
    }
}

#[no_mangle]
pub unsafe extern "C" fn wifi_lens_mac_vendor_index_free(index: *mut WiFiLensMacVendorIndex) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if !index.is_null() {
            unsafe {
                drop(Box::from_raw(index));
            }
        }
    }));
}

#[cfg(test)]
mod opaque_index_ffi_tests {
    use super::*;

    #[test]
    fn owned_index_reuses_prefix_map_and_handles_capacity_and_null_free() {
        let strings = b"001122334Small0011224Medium001133Large".to_vec();
        let entries = vec![
            WiFiLensMacVendorLookupEntry {
                prefix_offset: 0,
                prefix_length: 9,
                prefix_length_bits: 36,
                organization_offset: 9,
                organization_length: 5,
            },
            WiFiLensMacVendorLookupEntry {
                prefix_offset: 14,
                prefix_length: 7,
                prefix_length_bits: 28,
                organization_offset: 21,
                organization_length: 6,
            },
            WiFiLensMacVendorLookupEntry {
                prefix_offset: 27,
                prefix_length: 6,
                prefix_length_bits: 24,
                organization_offset: 33,
                organization_length: 5,
            },
        ];
        let mut handle = std::ptr::null_mut();
        assert_eq!(
            unsafe {
                wifi_lens_mac_vendor_index_build(
                    entries.as_ptr(),
                    entries.len(),
                    strings.as_ptr(),
                    strings.len(),
                    &mut handle,
                )
            },
            crate::WIFI_LENS_STATUS_OK
        );
        assert!(!handle.is_null());
        assert_eq!(unsafe { (*handle).index_builds }, 1);
        drop(strings);
        drop(entries);
        for (mac, code, expected) in [
            (b"00:11:22:33:44:55".as_slice(), 3, "Small"),
            (b"00:11:22:44:55:66", 3, "Medium"),
            (b"00:11:33:44:55:66", 3, "Large"),
            (b"10:20:30:40:50:60", 1, ""),
            (b"02:11:22:33:44:55", 2, ""),
            (b"01:11:22:33:44:55", 0, ""),
            (b"00:00:00:00:00:00", 0, ""),
        ] {
            let mut output = [0u8; 16];
            let mut length = 99;
            let mut result = -1;
            let status = unsafe {
                wifi_lens_mac_vendor_index_lookup(
                    handle,
                    mac.as_ptr(),
                    mac.len(),
                    output.as_mut_ptr(),
                    output.len(),
                    &mut length,
                    &mut result,
                )
            };
            assert_eq!(status, crate::WIFI_LENS_STATUS_OK);
            assert_eq!(result, code);
            assert_eq!(&output[..length], expected.as_bytes());
        }
        assert_eq!(unsafe { (*handle).index_builds }, 1);
        let mut length = 0;
        let mut result = 0;
        assert_eq!(
            unsafe {
                wifi_lens_mac_vendor_index_lookup(
                    handle,
                    b"00:11:22:33:44:55".as_ptr(),
                    17,
                    std::ptr::null_mut(),
                    0,
                    &mut length,
                    &mut result,
                )
            },
            crate::WIFI_LENS_STATUS_OUTPUT_TOO_SMALL
        );
        assert_eq!(length, 5);
        unsafe {
            wifi_lens_mac_vendor_index_free(handle);
            wifi_lens_mac_vendor_index_free(std::ptr::null_mut());
        }
    }

    #[test]
    fn build_failure_nulls_handle_and_validates_utf8_and_ranges() {
        let mut output = 1usize as *mut WiFiLensMacVendorIndex;
        let bad = [0xff];
        let entry = WiFiLensMacVendorLookupEntry {
            prefix_offset: 0,
            prefix_length: 1,
            prefix_length_bits: 24,
            organization_offset: 0,
            organization_length: 1,
        };
        assert_ne!(
            unsafe {
                wifi_lens_mac_vendor_index_build(&entry, 1, bad.as_ptr(), bad.len(), &mut output)
            },
            crate::WIFI_LENS_STATUS_OK
        );
        assert!(output.is_null());
        let invalid_range = WiFiLensMacVendorLookupEntry {
            prefix_offset: 1,
            prefix_length: 1,
            prefix_length_bits: 24,
            organization_offset: 0,
            organization_length: 1,
        };
        assert_eq!(
            unsafe {
                wifi_lens_mac_vendor_index_build(&invalid_range, 1, b"A".as_ptr(), 1, &mut output)
            },
            crate::WIFI_LENS_STATUS_INVALID_INPUT_SLICE
        );
        assert!(output.is_null());
        let invalid_utf8 = WiFiLensMacVendorLookupEntry {
            prefix_offset: 0,
            prefix_length: 2,
            prefix_length_bits: 24,
            organization_offset: 0,
            organization_length: 1,
        };
        let mixed = [b'0', 0xff];
        assert_eq!(
            unsafe {
                wifi_lens_mac_vendor_index_build(
                    &invalid_utf8,
                    1,
                    mixed.as_ptr(),
                    mixed.len(),
                    &mut output,
                )
            },
            crate::WIFI_LENS_STATUS_INVALID_UTF8
        );
        assert!(output.is_null());
        assert!(output.is_null());
        assert_eq!(
            unsafe {
                wifi_lens_mac_vendor_index_build(
                    std::ptr::null(),
                    1,
                    std::ptr::null(),
                    0,
                    &mut output,
                )
            },
            crate::WIFI_LENS_STATUS_INVALID_POINTER
        );
    }
}

const SHA256_K: [u32; 64] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

fn sha256(data: &[u8]) -> [u8; 32] {
    let mut state = [
        0x6a09e667u32,
        0xbb67ae85,
        0x3c6ef372,
        0xa54ff53a,
        0x510e527f,
        0x9b05688c,
        0x1f83d9ab,
        0x5be0cd19,
    ];
    let bit_length = (data.len() as u64).wrapping_mul(8);
    let mut padded = data.to_vec();
    padded.push(0x80);
    while padded.len() % 64 != 56 {
        padded.push(0);
    }
    padded.extend_from_slice(&bit_length.to_be_bytes());

    for chunk in padded.chunks_exact(64) {
        let mut words = [0u32; 64];
        for (index, word) in words.iter_mut().enumerate().take(16) {
            *word = u32::from_be_bytes([
                chunk[index * 4],
                chunk[index * 4 + 1],
                chunk[index * 4 + 2],
                chunk[index * 4 + 3],
            ]);
        }
        for index in 16..64 {
            let s0 = words[index - 15].rotate_right(7)
                ^ words[index - 15].rotate_right(18)
                ^ (words[index - 15] >> 3);
            let s1 = words[index - 2].rotate_right(17)
                ^ words[index - 2].rotate_right(19)
                ^ (words[index - 2] >> 10);
            words[index] = words[index - 16]
                .wrapping_add(s0)
                .wrapping_add(words[index - 7])
                .wrapping_add(s1);
        }

        let mut working = state;
        for (index, word) in words.iter().enumerate() {
            let s1 = working[4].rotate_right(6)
                ^ working[4].rotate_right(11)
                ^ working[4].rotate_right(25);
            let choice = (working[4] & working[5]) ^ ((!working[4]) & working[6]);
            let temporary1 = working[7]
                .wrapping_add(s1)
                .wrapping_add(choice)
                .wrapping_add(SHA256_K[index])
                .wrapping_add(*word);
            let s0 = working[0].rotate_right(2)
                ^ working[0].rotate_right(13)
                ^ working[0].rotate_right(22);
            let majority =
                (working[0] & working[1]) ^ (working[0] & working[2]) ^ (working[1] & working[2]);
            let temporary2 = s0.wrapping_add(majority);
            working = [
                temporary1.wrapping_add(temporary2),
                working[0],
                working[1],
                working[2],
                working[3].wrapping_add(temporary1),
                working[4],
                working[5],
                working[6],
            ];
        }
        for (destination, value) in state.iter_mut().zip(working) {
            *destination = destination.wrapping_add(value);
        }
    }

    let mut digest = [0u8; 32];
    for (index, value) in state.iter().enumerate() {
        digest[index * 4..index * 4 + 4].copy_from_slice(&value.to_be_bytes());
    }
    digest
}

fn sha256_hex(data: &[u8]) -> String {
    sha256(data)
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::{
        lookup_mac_vendor, normalize_mac_address, parse_csv, parse_mac_vendor_database, sha256_hex,
        MacVendorCancellationPoint, MacVendorEntry, MacVendorError, MacVendorLookup,
        MacVendorRegistry, MacVendorRegistryInput,
    };

    fn complete_inputs() -> Vec<(MacVendorRegistry, String)> {
        MacVendorRegistry::ALL
            .into_iter()
            .map(|registry| {
                let assignment = match registry {
                    MacVendorRegistry::MaL => "001122",
                    MacVendorRegistry::MaM => "0011223",
                    MacVendorRegistry::MaS => "001122334",
                    MacVendorRegistry::Iab => "001122335",
                };
                (
                    registry,
                    format!(
                        "Registry,Assignment,Organization Name\n{},{assignment},Example\n",
                        registry.raw_name()
                    ),
                )
            })
            .collect()
    }

    fn minimums() -> Vec<(MacVendorRegistry, usize)> {
        MacVendorRegistry::ALL
            .into_iter()
            .map(|registry| (registry, 1))
            .collect()
    }

    #[test]
    fn sha256_matches_known_vector() {
        assert_eq!(
            sha256_hex(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }

    #[test]
    fn csv_reader_preserves_quoted_commas_and_crlf() {
        let rows = parse_csv("a,b\r\n\"x,y\",z\r\n", "x.csv", &|_| {
            Ok::<_, MacVendorError>(())
        })
        .unwrap();
        assert_eq!(rows, vec![vec!["a", "b"], vec!["x,y", "z"]]);
    }

    #[test]
    fn parser_sorts_longest_prefix_first_and_computes_sha256() {
        let owned = complete_inputs();
        let inputs: Vec<_> = owned
            .iter()
            .map(|(_, csv)| MacVendorRegistryInput {
                display_name: "fixture.csv",
                data: csv.as_bytes(),
            })
            .collect();
        let database = parse_mac_vendor_database(
            &inputs,
            &minimums(),
            16 * 1024 * 1024,
            32 * 1024 * 1024,
            |_| Ok::<_, MacVendorError>(()),
        )
        .unwrap();
        assert_eq!(database.entries.len(), 4);
        assert_eq!(database.entries[0].prefix_length_bits, 36);
        assert_eq!(database.registries[0].registry, MacVendorRegistry::MaL);
        assert_eq!(database.registries[0].sha256.len(), 64);
    }

    #[test]
    fn cancellation_preserves_all_four_points() {
        let owned = complete_inputs();
        let inputs: Vec<_> = owned
            .iter()
            .map(|(_, csv)| MacVendorRegistryInput {
                display_name: "fixture.csv",
                data: csv.as_bytes(),
            })
            .collect();
        for point in [
            MacVendorCancellationPoint::Routine,
            MacVendorCancellationPoint::BeforeFinalSort,
            MacVendorCancellationPoint::AfterFinalSort,
        ] {
            assert_eq!(
                parse_mac_vendor_database(
                    &inputs,
                    &minimums(),
                    16 * 1024 * 1024,
                    32 * 1024 * 1024,
                    |candidate| {
                        if candidate == point {
                            Err(MacVendorError::Cancelled)
                        } else {
                            Ok(())
                        }
                    },
                ),
                Err(MacVendorError::Cancelled),
                "cancellation point {point:?}"
            );
        }
    }

    #[test]
    fn mac_lookup_preserves_normalization_and_prefix_order() {
        let entries = [
            MacVendorEntry {
                prefix: "001122".to_string(),
                prefix_length_bits: 24,
                organization: "Large".to_string(),
            },
            MacVendorEntry {
                prefix: "0011223".to_string(),
                prefix_length_bits: 28,
                organization: "Medium".to_string(),
            },
            MacVendorEntry {
                prefix: "001122334".to_string(),
                prefix_length_bits: 36,
                organization: "Small".to_string(),
            },
        ];
        assert_eq!(
            normalize_mac_address("00-11-22-33-44-55").as_deref(),
            Some("001122334455")
        );
        assert_eq!(
            lookup_mac_vendor("00:11:22:33:44:55", &entries),
            MacVendorLookup::Registered
        );
        assert_eq!(
            lookup_mac_vendor("02:11:22:33:44:55", &entries),
            MacVendorLookup::LocallyAdministered
        );
        assert_eq!(
            lookup_mac_vendor("00:00:00:00:00:00", &entries),
            MacVendorLookup::Invalid
        );
        assert_eq!(
            lookup_mac_vendor("10:20:30:40:50:60", &entries),
            MacVendorLookup::Unknown
        );
    }
}

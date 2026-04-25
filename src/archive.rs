pub enum ArchiveType {
    Puff,
}

pub struct ArchiveInfo {
    pub archive_type: ArchiveType,
    pub entries: Vec<ArchiveEntry>,
}

pub enum ArchiveEntryType {
    File,
    Directory,
}

pub struct ArchiveEntry {
    pub relative_path: String,
    pub temp_file_start: u64,
    pub temp_file_size: u64,
    pub original_size: u64,
    pub entry_type: ArchiveEntryType,
}

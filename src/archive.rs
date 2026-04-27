use std::{
    fs::File,
    io::{Read, Seek, SeekFrom, Write},
    path::PathBuf,
};

use thiserror::Error;
use walkdir::WalkDir;

#[derive(Debug, Error)]
pub enum ArchiveError {
    #[error("Input path does not exist: {0}")]
    InputNotFound(PathBuf),
    #[error("Output path does not exist: {0}")]
    OutputNotFound(PathBuf),
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error("Failed to compute relative path for: {0}")]
    StripPrefix(PathBuf),
}

struct PuffImpl {}

impl Pack for PuffImpl {
    fn pack<R: Read, W: Write>(file_reader: &mut R, archive_writer: &mut W) -> std::io::Result<()> {
        todo!()
    }
}

impl Unpack for PuffImpl {
    fn unpack<R: Read, W: Write>(
        archive_reader: &mut R,
        file_writer: &mut W,
    ) -> std::io::Result<()> {
        todo!()
    }
}

#[derive(clap::ValueEnum, Clone, Default)]
pub enum ArchiveType {
    #[default]
    Puff,
}

impl ArchiveType {
    fn pack<R: Read, W: Write>(
        &self,
        file_reader: &mut R,
        archive_writer: &mut W,
    ) -> std::io::Result<()> {
        match self {
            ArchiveType::Puff => PuffImpl::pack(file_reader, archive_writer),
        }
    }
}

pub trait Pack {
    fn pack<R: Read, W: Write>(file_reader: &mut R, archive_writer: &mut W) -> std::io::Result<()>;
}

pub trait Unpack {
    fn unpack<R: Read, W: Write>(
        archive_reader: &mut R,
        file_writer: &mut W,
    ) -> std::io::Result<()>;
}

pub struct ArchiveInfo {
    pub archive_type: ArchiveType,
    pub entries: Vec<ArchiveEntry>,
}

impl ArchiveInfo {
    pub fn serialized_size(&self) -> usize {
        let archive_type_len = size_of::<ArchiveType>();
        let entries_count_len = size_of::<u64>();
        archive_type_len
            + entries_count_len
            + self
                .entries
                .iter()
                .map(|e| e.serialized_size())
                .sum::<usize>()
    }
}

pub enum ArchiveEntryType {
    File,
    Directory,
}

pub struct ArchiveEntry {
    pub relative_path: String,
    pub archive_start: u64,
    pub archive_size: u64,
    pub original_size: u64,
    pub entry_type: ArchiveEntryType,
}

impl ArchiveEntry {
    pub fn serialized_size(&self) -> usize {
        let path_len = size_of::<u64>();
        let entry_type_len = size_of::<ArchiveEntryType>();
        let offsets_len = size_of::<u64>();

        // archive start + archive size + original_size
        path_len + self.relative_path.len() + entry_type_len + offsets_len * 3
    }
}

fn resolve_output_base(input: &PathBuf, output: Option<PathBuf>) -> PathBuf {
    output.unwrap_or_else(|| {
        if input.is_file() {
            input.clone()
        } else {
            input
                .parent()
                .unwrap_or_else(|| std::path::Path::new("."))
                .to_path_buf()
        }
    })
}

fn normalize_output_path(base: PathBuf, input: &PathBuf) -> Result<PathBuf, ArchiveError> {
    if base.extension().map_or(false, |e| e == "puff") {
        return Ok(base);
    }

    let name = input
        .file_name()
        .ok_or_else(|| ArchiveError::InputNotFound(input.clone()))?;

    if base.is_dir() {
        let mut out = base;
        out.push(name);
        out.set_extension("puff");
        Ok(out)
    } else {
        Ok(base.with_extension("puff"))
    }
}

fn get_temp_output_path(output: &PathBuf) -> PathBuf {
    let mut temp_out = output.clone();
    temp_out.push(".temp");
    temp_out
}

pub fn pack(
    input: PathBuf,
    output: Option<PathBuf>,
    archive_type: ArchiveType,
) -> Result<(), ArchiveError> {
    if !input.exists() {
        return Err(ArchiveError::InputNotFound(input));
    }

    let abs_input = std::fs::canonicalize(input)?;

    let base = resolve_output_base(&abs_input, output);
    let output = normalize_output_path(base, &abs_input)?;
    // let temp_out = get_temp_output_path(&output);

    // let mut temp_file = File::create(temp_out)?;

    let mut archive_info = ArchiveInfo {
        archive_type: archive_type.clone(),
        entries: WalkDir::new(&abs_input)
            .into_iter()
            .filter_map(|e| e.ok())
            .map(|e| -> Result<ArchiveEntry, ArchiveError> {
                let relative_path = e
                    .path()
                    .strip_prefix(&abs_input)
                    .map_err(|_| ArchiveError::StripPrefix(e.path().to_path_buf()))?
                    .to_string_lossy()
                    .to_string();
                if e.file_type().is_dir() {
                    return Ok(ArchiveEntry {
                        entry_type: ArchiveEntryType::Directory,
                        original_size: 0,
                        relative_path: relative_path,
                        archive_size: 0,
                        archive_start: 0,
                    });
                }

                return Ok(ArchiveEntry {
                    archive_size: 0,
                    archive_start: 0,
                    entry_type: ArchiveEntryType::File,
                    original_size: 0,
                    relative_path: relative_path,
                });
            })
            .collect::<Result<Vec<ArchiveEntry>, ArchiveError>>()?,
    };

    let mut archive_file = File::create(output)?;
    let header_length = archive_info.serialized_size();

    archive_file.seek(SeekFrom::Start(header_length as u64))?;

    for entry in archive_info.entries.iter_mut() {
        if matches!(entry.entry_type, ArchiveEntryType::Directory) {
            continue;
        }
        let full_path = abs_input.join(entry.relative_path.clone());
        let mut file = File::open(&full_path)?;
        let pre_pack_position = archive_file.stream_position()?;
        archive_type.pack(&mut file, &mut archive_file)?;
        let post_pack_position = archive_file.stream_position()?;

        entry.archive_start = pre_pack_position;
        entry.archive_size = post_pack_position - pre_pack_position;
        entry.original_size = file.stream_position()?;
    }

    todo!();
}

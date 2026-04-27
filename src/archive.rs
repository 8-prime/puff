use std::{
    io::{Read, Write},
    path::PathBuf,
};

use thiserror::Error;

#[derive(Debug, Error)]
pub enum ArchiveError {
    #[error("Input path does not exist: {0}")]
    InputNotFound(PathBuf),
    #[error("Output path does not exist: {0}")]
    OutputNotFound(PathBuf),
    #[error(transparent)]
    Io(#[from] std::io::Error),
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

fn get_temp_output_path(output: PathBuf) -> PathBuf {
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

    let base = resolve_output_base(&input, output);
    let output = normalize_output_path(base, &input)?;

    let mut archive_info = ArchiveInfo {
        archive_type: archive_type,
        entries: Vec::new(),
    };

    todo!()
}

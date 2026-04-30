use core::panic::PanicInfo;
use std::{
    convert::TryFrom,
    fmt,
    fs::File,
    io::{Read, Seek, SeekFrom, Write},
    path::PathBuf,
};

use humansize::{DECIMAL, format_size};
use thiserror::Error;
use walkdir::WalkDir;

const HEADER: [u8; 4] = *b"puff";

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
    #[error("File is not valid puff archive.")]
    InvalidArchive,
}

struct PuffImpl {}

impl Pack for PuffImpl {
    fn pack<R: Read, W: Write>(file_reader: &mut R, archive_writer: &mut W) -> std::io::Result<()> {
        let mut buf = [0u8; 1024];
        loop {
            let n = file_reader.read(&mut buf)?;
            if n == 0 {
                break; // EOF
            }
            archive_writer.write_all(&buf[..n])?;
        }
        Ok(())
    }
}

impl Unpack for PuffImpl {
    fn unpack<R: Read, W: Write>(
        archive_reader: &mut R,
        file_writer: &mut W,
    ) -> std::io::Result<()> {
        let mut buf = [0u8; 1024];
        loop {
            let n = archive_reader.read(&mut buf)?;
            if n == 0 {
                break; // EOF
            }
            file_writer.write_all(&buf[..n])?;
        }
        Ok(())
    }
}

#[derive(clap::ValueEnum, Clone, Default)]
pub enum ArchiveType {
    #[default]
    Puff,
}

impl TryFrom<u8> for ArchiveType {
    type Error = ArchiveError;
    fn try_from(v: u8) -> Result<Self, Self::Error> {
        match v {
            0 => Ok(ArchiveType::Puff),
            _ => Err(ArchiveError::InvalidArchive),
        }
    }
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

impl fmt::Display for ArchiveInfo {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        writeln!(
            f,
            "{}",
            match self.archive_type {
                ArchiveType::Puff => "Puff".to_string(),
            }
        )?;
        for entry in &self.entries {
            writeln!(f, "{}", entry)?;
        }
        Ok(())
    }
}

impl ArchiveInfo {
    pub fn serialized_size(&self) -> usize {
        let archive_type_len = size_of::<u8>();
        let entries_count_len = size_of::<u64>();
        HEADER.len()
            + archive_type_len
            + entries_count_len
            + self
                .entries
                .iter()
                .map(|e| e.serialized_size())
                .sum::<usize>()
    }

    pub fn serialize<W: Write>(&self, archive_writer: &mut W) -> std::io::Result<()> {
        archive_writer.write_all(&HEADER)?;
        archive_writer.write_all(&(self.archive_type.clone() as u8).to_le_bytes())?;
        archive_writer.write_all(&(self.entries.len() as u64).to_le_bytes())?;
        for entry in self.entries.iter() {
            entry.serialize(archive_writer)?;
        }
        return Ok(());
    }
}

#[derive(clap::ValueEnum, Clone)]
pub enum ArchiveEntryType {
    File,
    Directory,
}

impl TryFrom<u8> for ArchiveEntryType {
    type Error = ArchiveError;
    fn try_from(v: u8) -> Result<Self, Self::Error> {
        match v {
            0 => Ok(ArchiveEntryType::File),
            1 => Ok(ArchiveEntryType::Directory),
            _ => Err(ArchiveError::InvalidArchive),
        }
    }
}

pub struct ArchiveEntry {
    pub entry_type: ArchiveEntryType,
    pub archive_start: u64,
    pub archive_size: u64,
    pub original_size: u64,
    pub relative_path: String,
}

impl fmt::Display for ArchiveEntry {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let type_char = match self.entry_type {
            ArchiveEntryType::File => 'F',
            ArchiveEntryType::Directory => 'D',
        };
        let size_str = match self.entry_type {
            ArchiveEntryType::File => format_size(self.original_size, DECIMAL),
            ArchiveEntryType::Directory => "-".to_string(),
        };
        let compressed_size_str = match self.entry_type {
            ArchiveEntryType::File => format_size(self.archive_size, DECIMAL),
            ArchiveEntryType::Directory => "-".to_string(),
        };

        write!(
            f,
            "{}  {:>10} {:>10} {}",
            type_char, size_str, compressed_size_str, self.relative_path
        )
    }
}

impl ArchiveEntry {
    pub fn serialized_size(&self) -> usize {
        let path_len = size_of::<u64>();
        let entry_type_len = size_of::<u8>();
        let offsets_len = size_of::<u64>();

        // archive start + archive size + original_size
        entry_type_len + offsets_len * 3 + path_len + self.relative_path.len()
    }

    pub fn serialize<W: Write>(&self, archive_writer: &mut W) -> std::io::Result<()> {
        archive_writer.write_all(&(self.entry_type.clone() as u8).to_le_bytes())?;
        archive_writer.write_all(&self.archive_start.to_le_bytes())?;
        archive_writer.write_all(&self.archive_size.to_le_bytes())?;
        archive_writer.write_all(&self.original_size.to_le_bytes())?;
        archive_writer.write_all(&(self.relative_path.len() as u64).to_le_bytes())?;
        archive_writer.write_all(self.relative_path.as_bytes())?;

        return Ok(());
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

pub fn ls(input: PathBuf) -> Result<ArchiveInfo, ArchiveError> {
    if !input.exists() {
        return Err(ArchiveError::InputNotFound(input));
    }

    let abs_input = dunce::canonicalize(input)?;
    let mut archive_file = File::open(&abs_input)?;

    let mut header_bytes = [0u8; HEADER.len()];
    let read = archive_file.read(&mut header_bytes)?;
    if read != HEADER.len() || header_bytes != HEADER {
        return Err(ArchiveError::InvalidArchive);
    }

    let mut u8_buf = [0u8; 1];
    let mut u64_buf = [0u8; 8];

    archive_file.read_exact(&mut u8_buf)?;
    let archive_type = ArchiveType::try_from(u8_buf[0])?;

    archive_file.read_exact(&mut u64_buf)?;
    let entries_count = u64::from_le_bytes(u64_buf);

    let mut entries = Vec::with_capacity(entries_count as usize);
    for _ in 0..entries_count {
        archive_file.read_exact(&mut u8_buf)?;
        let entry_type = ArchiveEntryType::try_from(u8_buf[0])?;

        archive_file.read_exact(&mut u64_buf)?;
        let archive_start = u64::from_le_bytes(u64_buf);

        archive_file.read_exact(&mut u64_buf)?;
        let archive_size = u64::from_le_bytes(u64_buf);

        archive_file.read_exact(&mut u64_buf)?;
        let original_size = u64::from_le_bytes(u64_buf);

        archive_file.read_exact(&mut u64_buf)?;
        let path_len = u64::from_le_bytes(u64_buf);

        let mut path_buf = vec![0u8; path_len as usize];
        archive_file.read_exact(&mut path_buf)?;
        let relative_path =
            String::from_utf8(path_buf).map_err(|_| ArchiveError::InvalidArchive)?;

        entries.push(ArchiveEntry {
            entry_type,
            archive_start,
            archive_size,
            original_size,
            relative_path,
        });
    }

    Ok(ArchiveInfo {
        archive_type,
        entries,
    })
}

pub fn pack(
    input: PathBuf,
    output: Option<PathBuf>,
    archive_type: ArchiveType,
) -> Result<(), ArchiveError> {
    if !input.exists() {
        return Err(ArchiveError::InputNotFound(input));
    }

    let abs_input = dunce::canonicalize(input)?;

    let base = resolve_output_base(&abs_input, output);
    let output = normalize_output_path(base, &abs_input)?;

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
        let full_path = if entry.relative_path.is_empty() {
            abs_input.clone()
        } else {
            abs_input.join(&entry.relative_path)
        };
        let mut file = File::open(&full_path)?;
        let pre_pack_position = archive_file.stream_position()?;
        archive_type.pack(&mut file, &mut archive_file)?;
        let post_pack_position = archive_file.stream_position()?;

        entry.archive_start = pre_pack_position;
        entry.archive_size = post_pack_position - pre_pack_position;
        entry.original_size = file.stream_position()?;
    }

    archive_file.seek(SeekFrom::Start(0))?;
    archive_info.serialize(&mut archive_file)?;

    return Ok(());
}

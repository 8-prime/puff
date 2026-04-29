use std::path::PathBuf;

use clap::{Parser, Subcommand};

use crate::archive::ArchiveError;

mod archive;
mod interface;
#[derive(Parser)]
#[command(version, about = "A custom archive tool")]
struct Args {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Pack a directory or file into a .puff archive
    Pack {
        /// Path to pack
        path: PathBuf,
        /// Output directory (defaults to current directory)
        output_dir: Option<PathBuf>,
        /// Archive type (defaults to puff)
        #[arg(long, default_value_t, value_enum)]
        archive_type: archive::ArchiveType,
    },
    /// List the contents of a .puff archive
    Ls {
        /// Path to the .puff archive
        path: PathBuf,
    },
    /// Unpack a .puff archive
    Unpack {
        /// Path to the .puff archive
        path: PathBuf,
        /// Output directory (defaults to current directory)
        output_dir: Option<PathBuf>,
    },
}

fn main() -> Result<(), ArchiveError> {
    let args = Args::parse();

    match args.command {
        Command::Pack {
            path,
            output_dir,
            archive_type,
        } => {
            archive::pack(path, output_dir, archive_type)?;
        }
        Command::Ls { path } => {
            println!("Listing {:?}", path);
        }
        Command::Unpack { path, output_dir } => {
            println!("Unpacking {:?} -> {:?}", path, output_dir);
        }
    }

    Ok(())
}

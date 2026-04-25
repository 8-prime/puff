use std::io::Read;

struct A {}
impl InternalRead for A {
    fn read() {
        print!("I'm a")
    }
}

struct B {}

impl InternalRead for B {
    fn read() {
        print!("I'm b")
    }
}

enum C {
    D,
    E,
}

impl From<u8> for C {
    fn from(value: u8) -> Self {
        match value {
            0 => C::D,
            1 => C::E,
            _ => panic!("Fuck you. That type doesn't exist"),
        }
    }
}

impl ReadFile for C {
    fn read(&self) {
        match self {
            C::D => A::read(),
            C::E => B::read(),
        }
    }
}

trait InternalRead {
    fn read();
}

pub trait ReadFile {
    fn read(&self);
}

pub fn test() {
    let test_val: C = 0.into();

    test_val.read();
}

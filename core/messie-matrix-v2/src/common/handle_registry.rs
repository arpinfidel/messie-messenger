pub type Handle = u64; // upper 32 bits = generation, lower 32 bits = index

#[derive(Default)]
pub struct Slot<T> {
    pub gen: u32,
    pub occupied: bool,
    pub value: Option<T>,
}

pub struct Registry<T> {
    pub slots: Vec<Slot<T>>,
    pub free: Vec<u32>,
}

impl<T> Default for Registry<T> {
    fn default() -> Self {
        Self { slots: Vec::new(), free: Vec::new() }
    }
}

impl<T> Registry<T> {
    pub fn insert(&mut self, value: T) -> Handle {
        let (idx_u32, gen) = if let Some(idx) = self.free.pop() {
            (idx, self.slots[idx as usize].gen.wrapping_add(1))
        } else {
            let idx = self.slots.len() as u32;
            self.slots.push(Slot { gen: 0, occupied: false, value: None });
            (idx, 0)
        };
        let idx = idx_u32 as usize;
        self.slots[idx].gen = gen;
        self.slots[idx].occupied = true;
        self.slots[idx].value = Some(value);
        Self::make_handle(idx_u32, gen)
    }
    pub fn get(&self, handle: Handle) -> Option<&T> {
        let (idx, gen) = Self::split_handle(handle);
        let slot = self.slots.get(idx as usize)?;
        if slot.occupied && slot.gen == gen { slot.value.as_ref() } else { None }
    }
    #[inline]
    pub fn make_handle(idx: u32, gen: u32) -> Handle { ((gen as u64) << 32) | (idx as u64) }
    #[inline]
    pub fn split_handle(handle: Handle) -> (u32, u32) { let idx = (handle & 0xFFFF_FFFF) as u32; let gen = (handle >> 32) as u32; (idx, gen) }
}


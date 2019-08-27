// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

//! A simple histogram implementation for exponential histograms.

use std::collections::HashMap;

use serde::{Deserialize, Serialize};

pub use exponential::PrecomputedExponential;
pub use functional::Functional;

mod exponential;
mod functional;

/// A histogram.
///
/// Stores the counts per bucket and tracks the count of added samples and the total sum.
/// The bucketing algorithm can be changed.
///
/// ## Example
///
/// ```rust,ignore
/// let mut hist = Histogram::exponential(1, 500, 10);
///
/// for i in 1..=10 {
///     hist.accumulate(i);
/// }
///
/// assert_eq!(10, hist.count());
/// assert_eq!(55, hist.sum());
/// ```
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Histogram<B> {
    /// Mapping bucket's minimum to sample count.
    values: HashMap<u64, u64>,

    /// The count of samples added.
    count: u64,
    /// The total sum of samples.
    sum: u64,

    /// The bucketing algorithm used.
    bucketing: B,
}

/// A bucketing algorithm for histograms.
///
/// It's responsible to calculate the bucket a sample goes into.
/// It can calculate buckets on-the-fly or pre-calculate buckets and re-use that when needed.
pub trait Bucketing {
    /// Get the bucket's minimum value the sample falls into.
    fn sample_to_bucket_minimum(&self, sample: u64) -> u64;
}

impl<B: Bucketing> Histogram<B> {
    /// Get the number of buckets in this histogram.
    pub fn bucket_count(&self) -> usize {
        self.values.len()
    }

    /// Add a single value to this histogram.
    pub fn accumulate(&mut self, sample: u64) {
        let bucket_min = self.bucketing.sample_to_bucket_minimum(sample);
        let entry = self.values.entry(bucket_min).or_insert(0);
        *entry += 1;
        self.sum = self.sum.saturating_add(sample);
        self.count += 1;
    }

    /// Get the total sum of values recorded in this histogram.
    pub fn sum(&self) -> u64 {
        self.sum
    }

    /// Get the total count of values recorded in this histogram.
    pub fn count(&self) -> u64 {
        self.count
    }

    /// Get the filled values.
    pub fn values(&self) -> &HashMap<u64, u64> {
        &self.values
    }

    /// Check if this histogram recorded any values.
    pub fn is_empty(&self) -> bool {
        self.count() == 0
    }
}
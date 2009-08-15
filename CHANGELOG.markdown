PIPES CHANGELOG
===============

0.1.0 (August 15, 2009)
-----------------------

First release. All code is unstable and pending review.

### Processor

* Contains a few helper classes to make it easier to create common pipe elements.
* `Source` is used at the start to feed the rest of the chain with starting data.
* `Filter` makes it simple to filter stuff from the pipe.
* `Processor` now has a easy way to transform and react to the feed.

### ObjectProcessor

* Has matching classes to the generic Processor pipeline.
* Optimized for hashes or objects of properties.
* Each node in the pipe provides and/or requires specific properties.
* The pipe can optimize and validate itself based on each node's requirements.
* `ObjectSource` starts the feed.
* `ObjectFilter` filters the feed.
* `ObjectProcessor` transforms and reacts to the feed.

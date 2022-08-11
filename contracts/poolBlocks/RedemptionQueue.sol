// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library RedemptionQueue {
  struct Request {
    address owner;
    uint256 amount;
    uint256 time;
  }

  struct Queue {
    mapping(uint256 => Request) _internal;
    uint256 _first;
    uint256 _last;
  }

  function init(Queue storage _queue) public {
    _queue._first = 1;
  }

  function empty(Queue storage _queue) public view returns (bool) {
    return (_queue._last < _queue._first);
  }

  function get(Queue storage _queue) public view returns (Request storage data) {
    return _queue._internal[_queue._first];
  }

  function getBy(Queue storage _queue, uint256 _index) public view returns (Request storage data) {
    return _queue._internal[_index];
  }

  function enqueue(Queue storage _queue, Request memory _data) public {
    _queue._last += 1;
    _queue._internal[_queue._last] = _data;
  }

  function dequeue(Queue storage _queue) public returns (Request memory data) {
    require(_queue._last >= _queue._first); // non-empty queue

    data = _queue._internal[_queue._first];

    delete _queue._internal[_queue._first];
    _queue._first += 1;
  }

  function getAll(Queue storage _queue) public view returns (Request[] memory requests) {
    if (_queue._first > _queue._last) return new Request[](0);
    uint256 length = _queue._last - _queue._first + 1;
    requests = new Request[](length);
    for (uint256 i = 0; i < length; i++) {
      requests[i] = getBy(_queue, _queue._first + i);
    }
  }
}

/*
 * Free software licenced under 
 * GNU AFFERO GENERAL PUBLIC LICENSE
 * 
 * Check for document LICENCE forfull licence text
 * 
 * Luka Rahne
 */

//our parser was designed for lazy stream that is consumable
//unfortnatly redis socket streams doest work that way
//this class implements minimum requrement for redisparser

//currently parser requrement is take_n and take_while methods

part of redis;

// like Stream but has method next for simple reading
class StreamNext<T>  {
  late StreamSubscription<T> _ss;
  Queue<Completer<T>> _queue;
  int _nfut =0;
  int _npack=0;
  bool done=false;
  StreamNext.fromstream(Stream<T> stream): _queue = new Queue<Completer<T>>()
  {
    // _queue = new Queue<Completer<T>>();
    _nfut = 0;
    _npack = 0;
    done = false;
    _ss = stream.listen(onData  ,onError : this.onError  , onDone : this.onDone );
  }

  void onData(T event){
    if(_nfut >= 1){
      Completer  c = _queue.removeFirst();
      c.complete(event);
      _nfut -= 1; 
    }
    else{
      Completer<T> c = new Completer<T>();
      c.complete(event);
      _queue.addLast(c);
      _npack += 1;
    }
  }

  void onError(error){
    done = true;
    if(_nfut >= 1){
      _nfut = 0;
      for(Completer<T> e in  _queue){
        e.completeError(error);
      }
    }
  }

  void onDone(){
    onError("stream is closed");
  }

  Future<T> next(){
    if(_npack == 0){
      if(done) {
        return Future<T>.error("stream closed");
      }
      _nfut += 1;
      _queue.addLast(new Completer<T>());
      return _queue.last.future;
    }
    else {
      Completer<T> c = _queue.removeFirst();
      _npack -= 1;
      return c.future;
    }
  }
  
}

// it 
class LazyStream {
  
  StreamNext<List<int>> _stream;
  List<int> _remainder;
  List<int> _return;
  int _start_index=0;
  late Iterator<int> _iter;
  LazyStream.fromstream(Stream<List<int>> stream):_stream = new StreamNext<List<int>>.fromstream(stream),
  _return = new List<int>.empty(growable: true),_remainder = new List<int>.empty(growable: true)
  {
    // _stream = new StreamNext<List<int>>.fromstream(stream);
    // _start_index = 0;
    // _return = new List<int>.empty(growable: true);
    // _remainder = new List<int>.empty(growable: true);
    _iter = _remainder.iterator;
  }
  
  void close(){
     _stream.onDone();
  }

  Future<List<int>> take_n(int n) {
    print('take_n $n');
    _return = new List<int>.empty(growable: true);
    return __take_n(n);

  }
  
  Future<List<int>> __take_n(int n) {
    int rest = _take_n_helper(n);

    if (rest == 0){
        print('take_n END1 $n ret:$_return');
        return new Future<List<int>>.value(_return);
    }
    else {
      return _stream.next().then<List<int>>((List<int> pack){
        _remainder = pack;
        _iter = _remainder.iterator;
        print('take_n END2 $n ret:$_return');
        return __take_n(rest);
      });
    }
       
  }

  // return remining n
  int _take_n_helper(int n){
    while(n > 0 && _iter.moveNext()){
      _return.add(_iter.current);
      n--;
    }
    return n;
  }


  Future<List<int>> take_while(bool Function(int) pred) {
    _return = new List<int>.empty(growable: true);
    return __take_while(pred);
  }
  
  Future<List<int>> __take_while(bool Function(int) pred) {
    if (_take_while_helper(pred)){
        return Future<List<int>>.value(_return);
    }
    else {
      return _stream.next().then<List<int>>((List<int> rem){
        _remainder = rem;
        _iter = _remainder.iterator;
        return __take_while(pred);
      });
    }
  }

  // return true when exaused (when predicate returns false)
  bool _take_while_helper(bool Function(int) pred){
    while(_iter.moveNext()){
      if(pred(_iter.current)){
        _return.add(_iter.current);
      }
      else {
        return true;
      }
    }
    return false;
  }
}


// utils/deviceDiscovery.js
// 设备发现模块：mDNS 优先，UDP Fallback（修复模拟器 bind 错误）

const UDP_PORT = 16888;  // 保持 const
const MDNS_SERVICE_TYPE = '_smartdevice._tcp';

function parseDeviceFromMDNS(res) {
  const txt = res.txtRecords[0] || '';
  let data;
  try {
    data = JSON.parse(txt);
  } catch {
    return null;
  }
  return {
    uuid: data.uuid,
    name: data.name,
    devtype: data.devtype,
    protocol: data.protocol,
    ip: res.ip,
    port: res.port,
    online: true
  };
}

function parseDeviceFromUDP(message) {
  const data = JSON.parse(message);
  if (data.type === 'searchres') {
    return {
      ...data.data,
      online: true
    };
  }
  return null;
}

export function startDiscovery(callback) {
  return new Promise((resolve, reject) => {
    let devices = [];
    let isMDNSActive = false;
    let udpSocket = null;

    // 1. 尝试 mDNS
    wx.startLocalServiceDiscovery({
      serviceType: MDNS_SERVICE_TYPE,
      success: () => {
        isMDNSActive = true;
        console.log('mDNS 发现开始');
      },
      fail: (err) => {
        console.warn('mDNS 失败，回退 UDP:', err);
        startUDP();
      }
    });

    if (isMDNSActive) {
      wx.onLocalServiceFound((res) => {
        const device = parseDeviceFromMDNS(res);
        if (device && !devices.some(d => d.uuid === device.uuid)) {
          devices.push(device);
          console.log('mDNS 发现设备:', device);
        }
      });

      wx.onLocalServiceLost((res) => {
        devices = devices.filter(d => d.ip !== res.ip);
      });
    }

    // 2. UDP Fallback（修复：硬编码 port 数字，避模拟器转译）
    function startUDP() {
      console.log('启动 UDP Fallback');
      udpSocket = wx.createUDPSocket();
      
      // 修复：bind 用数字 16888，非变量
      udpSocket.bind({
        address: '0.0.0.0',
        port: 16888,  // ← 硬编码数字，防 [object Object]
        success: () => {
          console.log('UDP bind 成功，端口: 16888');
        },
        fail: (err) => {
          console.error('UDP bind 失败:', err);
          wx.showToast({ title: 'UDP 端口冲突，重试中...', icon: 'none' });
          if (udpSocket) udpSocket.close();
          return;
        }
      });

      const searchMsg = JSON.stringify({
        type: 'search',
        msgId: Date.now().toString(),
        ts: Date.now(),
        data: {}
      });

      // 发送（同样硬编码 port）
      udpSocket.send({
        address: '255.255.255.255',
        port: 16888,  // ← 硬编码
        message: searchMsg,
        success: () => {
          console.log('UDP 广播发送成功，包预览:', searchMsg.substring(0, 50) + '...');
        },
        fail: (err) => {
          console.error('UDP 发送失败:', err);
        }
      });

      udpSocket.onMessage((res) => {
        console.log('UDP 收到回复:', res.message.toString());
        const device = parseDeviceFromUDP(res.message);
        if (device && !devices.some(d => d.uuid === device.uuid)) {
          devices.push(device);
          console.log('UDP 发现设备:', device);
        }
      });

      // 5s 关闭
      setTimeout(() => {
        if (udpSocket) {
          udpSocket.close();
          udpSocket = null;
          console.log('UDP Socket 关闭');
        }
      }, 5000);
    }

    // 总是启动 UDP（测试用）
    startUDP();

    // 10s 停止
    setTimeout(() => {
      if (isMDNSActive) {
        wx.stopLocalServiceDiscovery();
      }
      if (callback) callback({ devices });
      console.log('发现结束，总设备数:', devices.length);
      resolve(devices);
    }, 10000);

    wx.onLocalServiceResolveFail((err) => {
      console.error('mDNS 解析失败:', err);
      startUDP();
    });
  });
}

export default { startDiscovery };
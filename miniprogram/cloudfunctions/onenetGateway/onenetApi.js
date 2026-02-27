const cloud = require('wx-server-sdk')
const axios = require('axios')
const { generateToken } = require('./token')

cloud.init({ env: cloud.DYNAMIC_CURRENT_ENV })
const db = cloud.database()

/**
 * 同步设备在线状态（带60秒缓存）
 */
async function syncDeviceOnline(devices) {

  if (!devices || devices.length === 0) return

  const now = Date.now()

  const needSync = devices.filter(dev =>
    !dev.lastSyncTime || (now - dev.lastSyncTime > 60000)
  )

  if (needSync.length === 0) return

  const groupMap = {}
  needSync.forEach(dev => {
    if (!groupMap[dev.productId]) {
      groupMap[dev.productId] = []
    }
    groupMap[dev.productId].push(dev)
  })

  for (const productId in groupMap) {

    const secretRes = await db.collection('product_secrets')
      .where({ productId, enable: true })
      .limit(1)
      .get()

    if (secretRes.data.length === 0) continue

    const accessKey = secretRes.data[0].accessKey

    const token = generateToken({
      accessKey,
      productId
    })

    const tasks = groupMap[productId].map(dev => {

      return axios.get(
        'https://iot-api.heclouds.com/device/detail',
        {
          params: {
            product_id: productId,
            device_name: dev.deviceName
          },
          headers: {
            Authorization: token
          },
          timeout: 5000
        }
      )
      .then(res => {
        const online = res.data?.data?.status === 1

        return db.collection('devices')
          .doc(dev._id)
          .update({
            data: {
              online,
              lastSyncTime: now
            }
          })
      })
      .catch(err => {
        console.error('同步失败:', dev.deviceName)
      })
    })

    await Promise.all(tasks)
  }
}
/**
 * 获取当前用户绑定的设备列表（含在线状态同步）
 */
async function getUserDevices(openid) {
  const userDevicesRes = await db.collection('user_devices')
    .where({ userOpenId: openid, enable: true })
    .orderBy('bindTime', 'desc')
    .get()

  if (userDevicesRes.data.length === 0) {
    return { code: 200, msg: 'success', data: [], total: 0 }
  }

  const deviceIds = userDevicesRes.data.map(item => item.deviceId)
  const devicesRes = await db.collection('devices')
    .where({ _id: db.command.in(deviceIds) })
    .get()

  await syncDeviceOnline(devicesRes.data)

  const refreshedRes = await db.collection('devices')
    .where({ _id: db.command.in(deviceIds) })
    .get()

  const deviceMap = new Map(refreshedRes.data.map(dev => [dev._id, dev]))

  const resultList = userDevicesRes.data.map(bind => {
    const dev = deviceMap.get(bind.deviceId) || {}
    return {
      deviceId: bind.deviceId,
      deviceName: dev.deviceName,
      productId: dev.productId,
      alias: bind.alias || dev.deviceName,
      room: bind.room || '未分组',
      role: bind.role || 'member',
      online: dev.online || false,
      state: dev.state || {},
      mac: dev.mac,
      createTime: dev.createTime,
      bindTime: bind.bindTime
    }
  })

  return {
    code: 200,
    msg: 'success',
    data: resultList,
    total: resultList.length
  }
}

/**
 * 获取单个设备详情（实时从 OneNET 拉取属性）
 */
async function getDeviceDetail(openid, deviceId) {
  if (!deviceId) {
    return { code: 400, msg: 'deviceId is required' }
  }

  const bindRes = await db.collection('user_devices')
    .where({ userOpenId: openid, deviceId, enable: true })
    .limit(1)
    .get()

  if (bindRes.data.length === 0) {
    return { code: 403, msg: '无权限访问该设备' }
  }

  const deviceRes = await db.collection('devices').doc(deviceId).get()
  if (!deviceRes.data) {
    return { code: 404, msg: '设备不存在' }
  }

  const dev = deviceRes.data
  const bind = bindRes.data[0]

  /* =============================
     查询产品能力（🔥新增）
  ============================== */
  const productRes = await db.collection('products')
    .where({ productId: dev.productId, enable: true })
    .limit(1)
    .get()

  let capabilities = []
  if (productRes.data.length > 0) {
    capabilities = productRes.data[0].capabilities || []
  }

  /* =============================
     获取 OneNET token
  ============================== */
  const secretRes = await db.collection('product_secrets')
    .where({ productId: dev.productId, enable: true })
    .limit(1)
    .get()

  if (secretRes.data.length === 0) {
    return { code: 404, msg: 'product secret not found' }
  }

  const token = generateToken({
    accessKey: secretRes.data[0].accessKey,
    productId: dev.productId
  })

  /* =============================
     拉取实时属性
  ============================== */
  const propertyRes = await axios.get(
    'https://iot-api.heclouds.com/thingmodel/query-device-property',
    {
      params: { product_id: dev.productId, device_name: dev.deviceName },
      headers: { Authorization: token },
      timeout: 8000
    }
  )

  const properties = propertyRes.data?.data || []
  const state = {}

  /* =============================
     根据能力自动类型转换（🔥核心升级）
  ============================== */
  properties.forEach(p => {

    const cap = capabilities.find(c => c.identifier === p.identifier)
    let value = p.value

    if (!cap) {
      state[p.identifier] = value
      return
    }

    // bool 类型
    if (cap.type === 'bool') {
      state[p.identifier] =
        value === true ||
        value === 1 ||
        value === '1' ||
        value === 'true'
      return
    }

    // schedule/json 类型
    if (cap.ui === 'schedule' && value) {
      try {
        const obj = JSON.parse(value)
        state[p.identifier] = {
          ver: obj.ver || 1,
          default_state:
            typeof obj.default_state === 'number'
              ? obj.default_state
              : 0,
          periods: Array.isArray(obj.periods) ? obj.periods : [],
          one_shot: Array.isArray(obj.one_shot) ? obj.one_shot : []
        }
      } catch {
        state[p.identifier] = {
          ver: 1,
          default_state: 0,
          periods: [],
          one_shot: []
        }
      }
      return
    }

    // 其它类型原样返回
    state[p.identifier] = value
  })

  /* =============================
     更新数据库缓存
  ============================== */
  const updateData = { lastSyncTime: Date.now() }
  Object.keys(state).forEach(key => {
    updateData[`state.${key}`] = state[key]
  })

  await db.collection('devices')
    .doc(deviceId)
    .update({ data: updateData })

  /* =============================
     返回结果
  ============================== */
  return {
    code: 200,
    msg: 'success',
    data: {
      deviceId: dev._id,
      deviceName: dev.deviceName,
      productId: dev.productId,
      alias: bind.alias || dev.deviceName,
      room: bind.room || '未分组',
      role: bind.role || 'member',
      online: dev.online || false,
      state,
      mac: dev.mac,
      createTime: dev.createTime,
      bindTime: bind.bindTime,
      capabilities
    }
  }
}


/**
 * 设置设备属性（下发指令）
 */
async function setProperty(productId, deviceName, params) {

  if (!productId || !deviceName) {
    return { code: 400, msg: 'productId 和 deviceName 必填' }
  }

  if (!params || Object.keys(params).length === 0) {
    return { code: 400, msg: 'params 不能为空' }
  }

  /* =============================
     获取产品密钥
  ============================== */

  const secretRes = await db.collection('product_secrets')
    .where({ productId, enable: true })
    .limit(1)
    .get()

  if (secretRes.data.length === 0) {
    return { code: 404, msg: 'product secret not found' }
  }

  const token = generateToken({
    accessKey: secretRes.data[0].accessKey,
    productId
  })

  /* =============================
     获取产品能力模型（用于类型修正）
  ============================== */

  const productRes = await db.collection('products')
    .where({ productId, enable: true })
    .limit(1)
    .get()

  const capabilities = productRes.data[0]?.capabilities || []

  const typeMap = {}
  capabilities.forEach(c => {
    typeMap[c.identifier] = c.type
  })

  /* =============================
     构造发送参数（类型修正）
  ============================== */

  const sendParams = {}

  for (const key in params) {

    let value = params[key]
    const type = typeMap[key]

    // ---- schedule 特殊处理 ----
    if (key === 'schedule') {

      let scheduleObj = value

      if (typeof scheduleObj === 'string') {
        try {
          scheduleObj = JSON.parse(scheduleObj)
        } catch {
          return { code: 400, msg: 'schedule JSON 格式错误' }
        }
      }

      scheduleObj.ver = scheduleObj.ver || 1
      scheduleObj.default_state =
        typeof scheduleObj.default_state === 'number'
          ? scheduleObj.default_state
          : 0

      scheduleObj.periods = Array.isArray(scheduleObj.periods)
        ? scheduleObj.periods
        : []

      scheduleObj.one_shot = Array.isArray(scheduleObj.one_shot)
        ? scheduleObj.one_shot
        : []

      sendParams[key] = JSON.stringify(scheduleObj)

      // 数据库存对象
      params[key] = scheduleObj

      continue
    }

    // ---- 类型自动修正 ----
    if (type === 'bool') {

      if (value === 'true') value = true
      if (value === 'false') value = false
      value = Boolean(value)

    } else if (type === 'int') {

      value = Number(value)
      if (isNaN(value)) {
        return { code: 400, msg: `${key} 必须为整数` }
      }

    } else if (type === 'float') {

      value = Number(value)
      if (isNaN(value)) {
        return { code: 400, msg: `${key} 必须为数字` }
      }

    } else if (type === 'string') {

      value = String(value)

    }

    sendParams[key] = value
    params[key] = value
  }

  /* =============================
     下发到 OneNET
  ============================== */

  const url = 'https://iot-api.heclouds.com/thingmodel/set-device-property'

  const body = {
    product_id: productId,
    device_name: deviceName,
    params: sendParams
  }

  const result = await axios.post(url, body, {
    headers: {
      Authorization: token,
      'Content-Type': 'application/json'
    },
    timeout: 10000
  })

  if (result.data.code !== 0 && result.data.code !== 200) {
    return {
      code: result.data.code,
      msg: result.data.msg || '下发失败'
    }
  }

  /* =============================
     更新数据库
  ============================== */

  const deviceRes = await db.collection('devices')
    .where({ productId, deviceName })
    .limit(1)
    .get()

  if (deviceRes.data.length > 0) {

    const deviceId = deviceRes.data[0]._id
    const updateData = {
      lastSyncTime: Date.now()
    }

    Object.keys(params).forEach(key => {
      updateData[`state.${key}`] = params[key]
    })

    await db.collection('devices')
      .doc(deviceId)
      .update({ data: updateData })
  }

  return {
    code: 200,
    msg: 'success',
    data: result.data.data
  }
}



/**
 * 添加/绑定设备
 */
async function addDevice(openid, { productId, deviceName }) {
  if (!productId || !deviceName) {
    return { code: 400, msg: 'productId 和 deviceName 不能为空' }
  }

  const secretRes = await db.collection('product_secrets')
    .where({ productId, enable: true })
    .limit(1)
    .get()

  if (secretRes.data.length === 0) {
    return { code: 404, msg: '未找到产品密钥' }
  }

  const token = generateToken({ accessKey: secretRes.data[0].accessKey, productId })

  // 检查 OneNET 是否存在
  let onenetDevice
  try {
    const checkRes = await axios.get('https://iot-api.heclouds.com/device/detail', {
      params: { product_id: productId, device_name: deviceName },
      headers: { Authorization: token },
      timeout: 5000
    })
    onenetDevice = checkRes.data?.data
    if (!onenetDevice) throw new Error('设备不存在')
  } catch {
    return { code: 404, msg: '设备未在平台预创建，请联系厂家' }
  }

  // 检查本地是否已存在
  const existRes = await db.collection('devices')
    .where({ productId, deviceName })
    .limit(1)
    .get()

  let deviceId

  if (existRes.data.length > 0) {
    deviceId = existRes.data[0]._id

    const bindCheck = await db.collection('user_devices')
      .where({ deviceId })
      .limit(1)
      .get()

    if (bindCheck.data.length > 0) {
      if (bindCheck.data[0].userOpenId === openid) {
        return { code: 200, msg: '设备已绑定，无需重复添加', data: { deviceId } }
      }
      return { code: 403, msg: '该设备已被其他用户绑定' }
    }
  } else {
    // 新建设备记录
    const insertRes = await db.collection('devices').add({
      data: {
        productId,
        deviceName,
        mac: deviceName,
        state: {},
        online: onenetDevice.status === 1,
        lastSyncTime: Date.now(),
        enable: true,
        createTime: Date.now()
      }
    })
    deviceId = insertRes._id
  }

  // 绑定用户
  await db.collection('user_devices').add({
    data: {
      userOpenId: openid,
      deviceId,
      alias: deviceName,
      role: 'owner',
      enable: true,
      room: '默认房间',
      bindTime: Date.now()
    }
  })

  return {
    code: 200,
    msg: '设备绑定成功',
    data: { deviceId, deviceName, productId }
  }
}

/**
 * 解除绑定（仅删除绑定关系，不删设备本身）
 */
async function unbindDevice(openid, deviceId) {
  if (!deviceId) return { code: 400, msg: 'deviceId 不能为空' }

  const bindRes = await db.collection('user_devices')
    .where({ userOpenId: openid, deviceId, role: 'owner' })
    .limit(1)
    .get()

  if (bindRes.data.length === 0) {
    return { code: 403, msg: '无权限解除绑定该设备（需为拥有者）' }
  }

  const removeRes = await db.collection('user_devices')
    .where({ userOpenId: openid, deviceId })
    .remove()

  if (removeRes.stats.removed === 0) {
    return { code: 404, msg: '绑定记录不存在或已删除' }
  }

  return { code: 200, msg: '设备已解除绑定', data: { deviceId } }
}

/**
 * 更新设备别名（仅 owner 可操作）
 */
async function updateAlias(openid, { deviceId, alias }) {
  if (!deviceId || !alias) {
    return { code: 400, msg: 'deviceId 和 alias 不能为空' }
  }

  const bindRes = await db.collection('user_devices')
    .where({ userOpenId: openid, deviceId, role: 'owner' })
    .limit(1)
    .get()

  if (bindRes.data.length === 0) {
    return { code: 403, msg: '无权限修改该设备别名（需为拥有者）' }
  }

  const updateRes = await db.collection('user_devices')
    .where({ userOpenId: openid, deviceId })
    .update({
      data: {
        alias: alias.trim(),
        updateTime: Date.now()
      }
    })

  if (updateRes.stats.updated === 0) {
    return { code: 404, msg: '绑定记录不存在或已删除' }
  }

  return {
    code: 200,
    msg: '别名更新成功',
    data: { deviceId, alias: alias.trim() }
  }
}

// ────────────────────────────────────────────────
// 主入口函数 → 只负责路由分发
// ────────────────────────────────────────────────
async function callOneNET(event) {
  const wxContext = cloud.getWXContext()
  const openid = wxContext.OPENID

  if (!openid) {
    return { code: 401, msg: '无法获取用户身份' }
  }

  const { subAction } = event

  try {
    switch (subAction) {
      case 'getUserDevices':
        return await getUserDevices(openid)

      case 'getDeviceDetail':
        return await getDeviceDetail(openid, event.deviceId)

      case 'setProperty':
        return await setProperty(event.productId, event.deviceName, event.params)

      case 'addDevice':
        return await addDevice(openid, event)

      case 'unbindDevice':
        return await unbindDevice(openid, event.deviceId)

      case 'updateAlias':
        return await updateAlias(openid, event)

      default:
        return { code: 400, msg: `不支持的 subAction: ${subAction}` }
    }
  } catch (err) {
    console.error(`[${subAction}] 执行失败:`, err)
    return {
      code: 500,
      msg: '服务器内部错误',
      error: err.message || String(err)
    }
  }
}

module.exports = { callOneNET }
